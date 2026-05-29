// Copyright (c) 2024, 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections;
using System.Collections.ObjectModel;
using System.IO.Compression;
using System.Management.Automation.Language;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Compiler.Analyser;
using Compiler.Module.Resolvable;
using Compiler.Requirements;
using Compiler.Text;
using LanguageExt;
using QuikGraph;
using QuikGraph.Algorithms;

namespace Compiler.Module.Compiled;

public partial class CompiledScript : CompiledLocalModule {
    private const string RuntimeModuleName = "AMT.PowerShell.Common";
    private static readonly Lazy<string> Template = new(() => {
        var info = Assembly.GetExecutingAssembly().GetName();
        using var templateStream = Assembly.GetExecutingAssembly().GetManifestResourceStream($"{info.Name}.Resources.ScriptTemplate.ps1")!;
        using var streamReader = new StreamReader(templateStream, Encoding.UTF8);
        return streamReader.ReadToEnd()[9..]; // Remove the #!ignore line.
    });

    public readonly BidirectionalGraph<Compiled, Edge<Compiled>> Graph = new();
    private readonly CompiledLocalArchiveModule RuntimeModule;

    public CompiledScript(
        PathedModuleSpec moduleSpec,
        CompiledDocument document,
        RequirementGroup requirements
    ) : base(moduleSpec, document, requirements) {
        this.RuntimeModule = GetRuntimeModule(moduleSpec.SourceRoot, requirements);
        this.RuntimeModule.RootScript = this;
        this.Graph.AddVertex(this);
        this.Graph.AddVertex(this.RuntimeModule);
        this.Graph.EdgeAdded += edge => {
            lock (edge.Target.Parents) {
                edge.Target.Parents.Add(edge.Source);
            }
        };
    }

    private CompiledScript(
        ResolvableScript thisResolvable,
        CompiledDocument document,
        RequirementGroup requirements
    ) : this(thisResolvable.ModuleSpec, document, requirements) { }

    public static async Task<Fin<CompiledScript>> Create(
        ResolvableScript thisResolvable,
        CompiledDocument document,
        ResolvableParent resolvableParent,
        RequirementGroup requirements
    ) {
        var script = new CompiledScript(thisResolvable, document, requirements) {
            ResolvableParent = resolvableParent,
        };

        var thisGraph = resolvableParent.GetGraphFromRoot(thisResolvable);
        var loadOrder = thisGraph.TopologicalSort();
        var reversedLoadOrder = loadOrder.Reverse();

        foreach (var resolvable in reversedLoadOrder) {
            var compiledRequirements = new List<Compiled>();
            foreach (var edge in thisGraph.OutEdges(resolvable)) {
                var requirement = script.Graph.Vertices.FirstOrDefault(module => module.ModuleSpec.Name == edge.Target.ModuleSpec.Name);

                if (requirement is null) {
                    if (GetCompiledFromSpec(resolvableParent, edge.Target.ModuleSpec).IsErr(out var error, out var compiled)) {
                        return error;
                    }

                    compiled.RootScript = script;
                    requirement = compiled;
                }

                compiledRequirements.Add(requirement);
            }

            Compiled? compiledModule = resolvable.ModuleSpec == thisResolvable.ModuleSpec ? script : null;
            if (compiledModule is null) {
                if (GetCompiledFromSpec(resolvableParent, resolvable.ModuleSpec).IsErr(out var error, out var compiled)) {
                    return error;
                }

                compiledModule = compiled;
            }

            script.Graph.AddVertex(compiledModule);
            if (compiledRequirements.Count != 0) {
                foreach (var requirement in compiledRequirements) {
                    script.Graph.AddVertex(requirement);
                    script.Graph.AddEdge(new Edge<Compiled>(compiledModule, requirement));
                }
            }

        }

        foreach (var compiled in script.Graph.Vertices.OfType<CompiledLocalModule>()) {
            if (compiled.ValidateRequirementsResolved().IsErr(out var error, out _)) {
                return error.Enrich(compiled.ModuleSpec);
            }
        }

        await Task.WhenAll(script.Graph.Vertices.Where(compiled => compiled is CompiledLocalModule).Select(async compiled => {
            var imports = script.Graph.OutEdges(compiled).Select(edge => edge.Target);
            var issues = await Analyser.Analyser.Analyse((CompiledLocalModule)compiled, [.. imports]);
            issues.ForEach(issue => Program.Errors.Add(issue.Enrich(compiled.ModuleSpec)));
        }));

        return script;
    }

    public override Fin<string> GetPowerShellObject() {
        var template = Template.Value;
        var embeddedModules = new StringBuilder();
        embeddedModules.AppendLine("$Script:EMBEDDED_MODULES = @(");
        foreach (var module in this.Graph.Vertices.Where(module => module != this.RuntimeModule)) {
            var moduleObjectResult = module switch {
                CompiledScript script when script == this => base.GetPowerShellObject(),
                _ => module.GetPowerShellObject()
            };

            if (moduleObjectResult.IsErr(out var moduleError, out var moduleObject)) {
                return moduleError;
            }

            var lineCount = moduleObject.Count(character => character == '\n');
            var skipLines = Enumerable.Range(6, lineCount - 6);
            embeddedModules.AppendLine(IndentString(moduleObject, 8, skipLines));
        }
        embeddedModules.AppendLine(IndentString(");", 4));

        var runtimeModuleObject = this.RuntimeModule.GetPowerShellObject().IfFail(string.Empty);

        var paramBlock = new StringBuilder();
        var scriptParamBlock = this.Document.Ast.ParamBlock;
        if (scriptParamBlock != null) {
            scriptParamBlock.Attributes.ToList().ForEach(attribute => paramBlock.AppendLine(attribute.Extent.Text));
            paramBlock.Append(scriptParamBlock.Extent.Text);
        } else {
            paramBlock.AppendLine("[CmdletBinding()]\nparam()");
        }

        var importOrder = string.Empty;
        if (this.Graph.VertexCount > 1) {
            var importNames = new List<string>();
            foreach (var module in this.Graph.TopologicalSort().Skip(1).Reverse()) {
                if (module.GetNameHash().IsErr(out var nameHashError, out var nameHash)) {
                    return nameHashError;
                }

                importNames.Add($"'{nameHash}'");
            }

            importOrder = importNames.Aggregate((a, b) => $"{a}, {b}");
        }

        var replacements = new Dictionary<string, string> {
            { "EMBEDDED_MODULES", embeddedModules.ToString() },
            { "PARAM_BLOCK", paramBlock.ToString() },
            { "IMPORT_ORDER", $"$Script:REMOVE_ORDER = @({importOrder});" },
            { "RUNTIME_MODULE", "$RUNTIME_MODULE = " + runtimeModuleObject },
            { "RUNTIME_MODULE_NAME", "$RUNTIME_MODULE_NAME = '" + RuntimeModuleName + "'" }
        };

        if (FillTemplate(template, replacements).IsErr(out var error, out var filledTemplate)) {
            Program.Errors.Add(error);
            return error;
        }

        return filledTemplate;
    }

    public override CompiledScript GetRootParent() => this;

    private static string IndentString(string str, int indentBy, IEnumerable<int>? skipLines = null) {
        if (!Program.IsDebugging) { return str; }

        var indent = new string(' ', indentBy);
        var lines = str.Split('\n');
        var indentedLines = lines.Select((line, index) => {
            if (string.IsNullOrWhiteSpace(line)) { return line; }
            if (skipLines != null && skipLines.Contains(index)) { return line; }
            return indent + line;
        });

        return string.Join('\n', indentedLines);
    }

    private static Fin<string> FillTemplate(string template, Dictionary<string, string> replacements) {
        if (AstHelper.GetAstReportingErrors(template, None, [], out var tokens).IsErr(out var err, out var ast)) {
            return err;
        }

        if (tokens.Length == 0) { return template; }

        var defines = tokens
            .Where(token => token.Kind == TokenKind.Comment)
            .Select(token => (DefineRegex().Match(token.Text), token.Extent))
            .Where(match => match.Item1.Success)
            .Select(match => (match.Item1.Groups, match.Extent))
            .ToList();

        var editor = new TextEditor(new TextDocument(template.Split('\n')));
        defines.ForEach(define => {
            var (groups, extent) = define;
            var name = groups["name"].Value;
            var args = groups["args"]?.Value;
            var removeBefore = args?.Contains('<') ?? false;
            var removeAfter = args?.Contains('>') ?? false;

            if (replacements.TryGetValue(name, out var replacement)) {
                editor.AddExactEdit(
                    extent.StartLineNumber - 1,
                    removeBefore ? 0 : (extent.StartColumnNumber - 1),
                    extent.EndLineNumber - 1,
                    removeAfter
                        ? editor.Document.GetLines((_, index) => index >= extent.EndLineNumber)[extent.EndLineNumber - 1].Length
                        : (extent.EndColumnNumber - 1),
                    UpdateOptions.InsertInline,
                    _ => replacement.Split('\n')
                );
            } else {
                Program.Errors.Add(Issue.Error($"Could not find a replacement for the define '{name}'", extent, ast));
            }
        });

        return CompiledDocument.FromBuilder(editor).Map(doc => doc.GetContent());
    }

    [GeneratedRegex(@"!DEFINE\s+(?<name>\w+)(?:\s+(?<args>[<>]+))?", RegexOptions.Multiline)]
    private static partial Regex DefineRegex();

    private static Fin<Compiled> GetCompiledFromSpec(
        ResolvableParent resolvableParent,
        ModuleSpec moduleSpec
    ) => resolvableParent.Resolvables.GetValueOrDefault(moduleSpec).AsOption()
        .Bind(resolvableInfo => resolvableInfo.Compiled)
        .IfNone(() => Fin.Fail<Compiled>(Error.New($"No resolvable found for {moduleSpec}.")));

    private static CompiledLocalArchiveModule GetRuntimeModule(string sourceRoot, RequirementGroup requirements) {
        var assembly = Assembly.GetExecutingAssembly();
        var assemblyName = assembly.GetName().Name;
        var resourcePrefix = $"{assemblyName}.Resources.RuntimeModule.";

        var dllResourceName = $"{resourcePrefix}{RuntimeModuleName}.dll";
        var psd1ResourceName = $"{resourcePrefix}{RuntimeModuleName}.psd1";

        using var dllStream = assembly.GetManifestResourceStream(dllResourceName)
            ?? throw new InvalidOperationException($"Embedded runtime module DLL resource '{dllResourceName}' not found in compiler assembly. Ensure the pre-build target copies the runtime module files.");
        using var psd1Stream = assembly.GetManifestResourceStream(psd1ResourceName)
            ?? throw new InvalidOperationException($"Embedded runtime module PSD1 resource '{psd1ResourceName}' not found in compiler assembly. Ensure the pre-build target copies the runtime module files.");

        using var dllMemoryStream = new MemoryStream();
        dllStream.CopyTo(dllMemoryStream);
        var dllBytes = dllMemoryStream.ToArray();

        using var psd1MemoryStream = new MemoryStream();
        psd1Stream.CopyTo(psd1MemoryStream);
        var psd1Bytes = psd1MemoryStream.ToArray();

        // Build zip archive in-memory with both files at root level.
        var archiveBytes = BuildRuntimeModuleZip(dllBytes, psd1Bytes);

        // Parse manifest from PSD1 bytes via PowerShell.
        var psd1Content = Encoding.UTF8.GetString(psd1Bytes);
        var manifestResult = Program.RunPowerShell(psd1Content);
        var manifest = manifestResult.Match(
            Succ: objects => (Hashtable)objects[0].BaseObject,
            Fail: error => throw new InvalidOperationException($"Failed to parse runtime module manifest: {error}")
        );

        // Build PathedModuleSpec with synthetic path. Hash is computed from DLL bytes
        // and set via reflection to avoid filesystem access for embedded resources.
        var relativePath = $"embedded/{RuntimeModuleName}/{RuntimeModuleName}.psd1";
        var fullPath = Path.Combine(sourceRoot, relativePath);
        var spec = new PathedModuleSpec(sourceRoot, fullPath);

        var hash = SHA256.HashData(dllBytes);
        var lazyHashField = typeof(PathedModuleSpec).GetField("LazyHash", BindingFlags.NonPublic | BindingFlags.Instance)
            ?? throw new MissingFieldException("PathedModuleSpec.LazyHash field not found.");
        lazyHashField.SetValue(spec, Prelude.Some(hash));

        return new CompiledLocalArchiveModule(spec, requirements, archiveBytes, manifest) {
            ResolvableParent = null!
        };
    }

    private static byte[] BuildRuntimeModuleZip(byte[] dllBytes, byte[] psd1Bytes) {
        using var memoryStream = new MemoryStream();
        using (var archive = new ZipArchive(memoryStream, ZipArchiveMode.Create, true)) {
            var dllEntry = archive.CreateEntry($"{RuntimeModuleName}.dll", CompressionLevel.Optimal);
            using (var dllEntryStream = dllEntry.Open()) {
                dllEntryStream.Write(dllBytes, 0, dllBytes.Length);
            }

            var psd1Entry = archive.CreateEntry($"{RuntimeModuleName}.psd1", CompressionLevel.Optimal);
            using (var psd1EntryStream = psd1Entry.Open()) {
                psd1EntryStream.Write(psd1Bytes, 0, psd1Bytes.Length);
            }
        }

        return memoryStream.ToArray();
    }
}
