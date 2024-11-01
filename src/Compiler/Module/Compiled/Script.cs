// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation.Language;
using System.Reflection;
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
    private static readonly Lazy<string> Template = new(() => {
        var info = Assembly.GetExecutingAssembly().GetName();
        using var templateStream = Assembly.GetExecutingAssembly().GetManifestResourceStream($"{info.Name}.Resources.ScriptTemplate.ps1")!;
        using var streamReader = new StreamReader(templateStream, Encoding.UTF8);
        return streamReader.ReadToEnd()[9..]; // Remove the #!ignore line.
    });

    public virtual BidirectionalGraph<Compiled, Edge<Compiled>> Graph { get; } = new();

    public CompiledScript(
        PathedModuleSpec moduleSpec,
        CompiledDocument document,
        RequirementGroup requirements
    ) : base(moduleSpec, document, requirements) {
        this.Graph.AddVertex(this);
        // Add the parent-child relationships to each module.
        this.Graph.EdgeAdded += edge => edge.Target.Parents.Add(edge.Source);
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
        var script = new CompiledScript(thisResolvable, document, requirements);

        var thisGraph = resolvableParent.GetGraphFromRoot(thisResolvable);
        var loadOrder = thisGraph.TopologicalSort();
        var reversedLoadOrder = loadOrder.Reverse();

        foreach (var resolvable in reversedLoadOrder) {
            var compiledRequirements = new List<Compiled>();
            foreach (var edge in thisGraph.OutEdges(resolvable)) {
                var requirement = script.Graph.Vertices.FirstOrDefault(module => module.ModuleSpec == edge.Target.ModuleSpec);
                if (requirement is null) {
                    if ((await resolvableParent.WaitForCompiled(edge.Target.ModuleSpec)).IsErr(out var error, out var compiled)) {
                        return error;
                    }

                    requirement = compiled;
                }
                compiledRequirements.Add(requirement);
            }

            Compiled? compiledModule = resolvable.ModuleSpec == thisResolvable.ModuleSpec ? script : null;
            if (compiledModule is null) {
                if ((await resolvableParent.WaitForCompiled(resolvable.ModuleSpec)).IsErr(out var error, out var compiled)) {
                    return error;
                }

                compiledModule = compiled;
            }

            if (compiledRequirements.Count != 0) {
                script.Graph.AddVerticesAndEdgeRange(compiledRequirements.Select(requirement => new Edge<Compiled>(compiledModule, requirement)));
            } else {
                script.Graph.AddVertex(compiledModule);
            }
        }

        foreach (var edge in script.Graph.Vertices) {
            if (edge is not CompiledLocalModule compiled) { continue; }
            (await Analyser.Analyser.Analyse(compiled, script.Graph.OutEdges(compiled).Select(edge => edge.Target)))
                .ForEach(issue => Program.Errors.Add(issue.Enrich(compiled.ModuleSpec)));
        }

        await Task.WhenAll(script.Graph.Vertices.Where(compiled => compiled is CompiledLocalModule).Select(async compiled => {
            var imports = script.Graph.OutEdges(compiled).Select(edge => edge.Target);
            var issues = await Analyser.Analyser.Analyse((CompiledLocalModule)compiled, [.. imports]);
            issues.ForEach(issue => Program.Errors.Add(issue.Enrich(compiled.ModuleSpec)));
        }));

        return script;
    }

    public override string GetPowerShellObject() {
        var template = Template.Value;
        var embeddedModules = new StringBuilder();
        embeddedModules.AppendLine("$Script:EMBEDDED_MODULES = @(");
        this.Graph.Vertices.ToList().ForEach(module => {
            var moduleObject = module switch {
                CompiledScript script when script == this => base.GetPowerShellObject(),
                _ => module.GetPowerShellObject()
            };

            var lineCount = moduleObject.Count(character => character == '\n');
            // Only skip the lines of the content of the module object.
            var skipLines = Enumerable.Range(6, lineCount - 6);
            embeddedModules.AppendLine(IndentString(moduleObject, 8, skipLines));
        });
        embeddedModules.AppendLine(IndentString(");", 4));

        var paramBlock = new StringBuilder();
        var scriptParamBlock = this.Document.Ast.ParamBlock;
        if (scriptParamBlock != null) {
            scriptParamBlock.Attributes.ToList().ForEach(attribute => paramBlock.AppendLine(attribute.Extent.Text));
            paramBlock.Append(scriptParamBlock.Extent.Text);
        } else {
            paramBlock.AppendLine("[CmdletBinding()]\nparam()");
        }

        var importOrder = this.Graph.VertexCount > 1
            ? this.Graph.TopologicalSort()
                .Skip(1) // Skip the root node.
                .Reverse()
                .Select(module => $"'{module.GetNameHash()}'")
                .Aggregate((a, b) => $"{a}, {b}")
            : string.Empty;

        var replacements = new Dictionary<string, string> {
            { "EMBEDDED_MODULES", embeddedModules.ToString() },
            { "PARAM_BLOCK", paramBlock.ToString() },
            { "IMPORT_ORDER", $"$Script:REMOVE_ORDER = @({importOrder});" }
        };

        if (FillTemplate(template, replacements).IsErr(out var error, out var filledTemplate)) {
            Program.Errors.Add(error);
            return string.Empty;
        };

        return filledTemplate;
    }

    public override CompiledScript GetRootParent() => this;

    /// <summary>
    /// Utility method for indenting a string.
    ///
    /// As indentation is optional in PowerShell this will not add any indentations
    /// if the program is running without the Debug flag to conserve space.
    /// </summary>
    /// <param name="str">
    /// The string to indent.
    /// </param>
    /// <param name="indentBy">
    /// The amount of spaces to indent by.
    /// </param>
    /// <param name="skipLines">
    /// The lines to skip when indenting.
    /// </param>
    /// <returns>
    /// The indented string.
    /// </returns>
    private static string IndentString(string str, int indentBy, IEnumerable<int>? skipLines = null) {
        if (!Program.IsDebugging) { return str; }

        var indent = new string(' ', indentBy);
        var lines = str.Split('\n');
        var indentedLines = lines.Select((line, index) => {
            if (string.IsNullOrWhiteSpace(line)) { return line; } // Skip empty lines.
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
}
