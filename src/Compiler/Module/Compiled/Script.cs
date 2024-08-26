// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation.Language;
using System.Reflection;
using System.Text;
using Compiler.Module.Resolvable;
using Compiler.Requirements;
using Compiler.Text;
using NLog;
using QuikGraph;
using QuikGraph.Algorithms;

namespace Compiler.Module.Compiled;

public class CompiledScript : CompiledLocalModule {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public readonly ParamBlockAst? ScriptParamBlock;

    public readonly BidirectionalGraph<Compiled, Edge<Compiled>> Graph;

    public CompiledScript(
        PathedModuleSpec moduleSpec,
        TextEditor editor,
        ResolvableParent resolvableParent,
        ParamBlockAst? scriptParamBlock,
        RequirementGroup requirements
    ) : base(moduleSpec, CompiledDocument.FromBuilder(editor, 0), requirements) {
        this.ScriptParamBlock = scriptParamBlock;
        this.Graph = new BidirectionalGraph<Compiled, Edge<Compiled>>();
        _ = this.Graph.AddVertex(this);

        var loadOrder = resolvableParent.Graph.TopologicalSort();
        var reversedLoadOrder = loadOrder.Reverse();
        reversedLoadOrder.ToList().ForEach(resolvable => {
            Logger.Trace($"Compiling {resolvable.ModuleSpec.Name}");

            var compiledRequirements = resolvableParent.Graph
                .OutEdges(resolvable)
                .Select(edge => this.Graph.Vertices.First(module => module.ModuleSpec == edge.Target.ModuleSpec));

            var compiledModule = resolvable.ModuleSpec == moduleSpec ? this : resolvable.IntoCompiled();

            if (compiledRequirements.Any()) {
                _ = this.Graph.AddVerticesAndEdgeRange(compiledRequirements.Select(requirement => new Edge<Compiled>(compiledModule, requirement)));
            } else {
                _ = this.Graph.AddVertex(compiledModule);
            }
        });

        // Iterate over the graph and add the parent-child relationships.
        this.Graph.Edges.ToList().ForEach(edge => {
            edge.Target.Parents.Add(edge.Source);
        });

        Logger.Trace("Analyzing compiled modules.");
        this.Graph.Vertices.Where(compiled => compiled is CompiledLocalModule).ToList().ForEach(compiled => {
            var imports = this.Graph.OutEdges(compiled).Select(edge => edge.Target);
            Analyser.Analyser.Analyse((CompiledLocalModule)compiled, [.. imports])
                .ForEach(issue => Program.Errors.Add(issue.AsException()));
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
