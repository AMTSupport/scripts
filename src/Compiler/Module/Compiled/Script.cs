// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation;
using System.Management.Automation.Language;
using System.Reflection;
using System.Text;
using Compiler.Module.Resolvable;
using Compiler.Requirements;
using Compiler.Text;
using LanguageExt;
using NLog;
using QuikGraph;
using QuikGraph.Algorithms;
using QuikGraph.Graphviz;

namespace Compiler.Module.Compiled;

public class CompiledScript : CompiledLocalModule {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public readonly ParamBlockAst? ScriptParamBlock;

    public readonly BidirectionalGraph<Compiled, Edge<Compiled>> Graph;

    /// <summary>
    /// Creates a new compiled script.
    /// </summary>
    /// <param name="moduleSpec"></param>
    /// <param name="document"></param>
    /// <param name="resolvableParent"></param>
    /// <param name="scriptParamBlock"></param>
    /// <param name="requirements"></param>
    internal CompiledScript(
        ResolvableScript thisResolvable,
        CompiledDocument document,
        ResolvableParent resolvableParent,
        ParamBlockAst? scriptParamBlock,
        RequirementGroup requirements
    ) : base(thisResolvable.ModuleSpec, document, requirements) {
        this.ScriptParamBlock = scriptParamBlock;

        this.Graph = new BidirectionalGraph<Compiled, Edge<Compiled>>();
        this.Graph.AddVertex(this);
        // Add the parent-child relationships to each module.
        this.Graph.EdgeAdded += edge => edge.Target.Parents.Add(edge.Source);
        var thisGraph = resolvableParent.GetGraphFromRoot(thisResolvable);
        var dotGraph = thisGraph.ToGraphviz(alg => {
            alg.FormatVertex += (sender, args) => args.VertexFormat.Label = args.Vertex.ModuleSpec.Name;
        });
        Logger.Debug($"Graph for {thisResolvable.ModuleSpec.Name}:\n{dotGraph}");

        var loadOrder = thisGraph.TopologicalSort();
        var reversedLoadOrder = loadOrder.Reverse();
        reversedLoadOrder.ToList().ForEach(async resolvable => {
            var compiledRequirements = await Task.WhenAll(thisGraph
                .OutEdges(resolvable)
                .Select(async edge => {
                    return this.Graph.Vertices.FirstOrDefault(module => module.ModuleSpec == edge.Target.ModuleSpec)
                        ?? (await resolvableParent.WaitForCompiled(edge.Target.ModuleSpec)).ThrowIfFail();
                }));

            var compiledModule = resolvable.ModuleSpec == thisResolvable.ModuleSpec
                ? this
                : (await resolvableParent.WaitForCompiled(resolvable.ModuleSpec)).ThrowIfFail();

            if (compiledRequirements.Length != 0) {
                this.Graph.AddVerticesAndEdgeRange(
                    compiledRequirements.Select(requirement => new Edge<Compiled>(compiledModule, requirement))
                );
            } else {
                this.Graph.AddVertex(compiledModule);
            }
        });

        this.Graph.Vertices.Where(compiled => compiled is CompiledLocalModule).ToList().ForEach(compiled => {
            var imports = this.Graph.OutEdges(compiled).Select(edge => edge.Target);
            Analyser.Analyser.Analyse((CompiledLocalModule)compiled, [.. imports])
                .ForEach(issue => Program.Errors.Add(issue.ToErrorException()));
        });
    }

    public override string GetPowerShellObject() {
        var info = Assembly.GetExecutingAssembly().GetName();
        using var templateStream = Assembly.GetExecutingAssembly().GetManifestResourceStream($"{info.Name}.Resources.ScriptTemplate.ps1")!;
        using var streamReader = new StreamReader(templateStream, Encoding.UTF8);
        var template = streamReader.ReadToEnd();

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
        if (this.ScriptParamBlock != null) {
            this.ScriptParamBlock.Attributes.ToList().ForEach(attribute => paramBlock.AppendLine(attribute.Extent.Text));
            paramBlock.Append(this.ScriptParamBlock.Extent.Text);
        } else {
            paramBlock.AppendLine("[CmdletBinding()]\nparam()");
        }

        var importOrder = this.Graph.TopologicalSort()
            .Skip(1) // Skip the root node.
            .Reverse()
            .Select(module => $"'{module.GetNameHash()}'")
            .Aggregate((a, b) => $"{a}, {b}");

        // TODO - Implement a way to replace #!DEFINE macros in the template.
        // This could also be how we can implement secure variables during compilation.
        template = template
            .Replace("#!DEFINE EMBEDDED_MODULES", embeddedModules.ToString())
            .Replace("#!DEFINE PARAM_BLOCK", paramBlock.ToString())
            .Replace("#!DEFINE IMPORT_ORDER", $"$Script:REMOVE_ORDER = @({importOrder});");

        return template;
    }

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
}
