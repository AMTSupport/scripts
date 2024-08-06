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

public class CompiledScript : CompiledLocalModule
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public readonly ParamBlockAst? ScriptParamBlock;

    public readonly BidirectionalGraph<Compiled, Edge<Compiled>> Graph;

    public CompiledScript(
        PathedModuleSpec moduleSpec,
        TextEditor editor,
        ResolvableParent resolvableParent,
        ParamBlockAst? scriptParamBlock,
        RequirementGroup requirements
    ) : base(moduleSpec, CompiledDocument.FromBuilder(editor, 0), requirements)
    {
        ScriptParamBlock = scriptParamBlock;
        Graph = new BidirectionalGraph<Compiled, Edge<Compiled>>();
        Graph.AddVertex(this);

        var loadOrder = resolvableParent.Graph.TopologicalSort();
        var reversedLoadOrder = loadOrder.Reverse();
        reversedLoadOrder.ToList().ForEach(resolvable =>
        {
            Logger.Trace($"Compiling {resolvable.ModuleSpec.Name}");

            var compiledRequirements = resolvableParent.Graph
                .OutEdges(resolvable)
                .Select(edge => Graph.Vertices.First(module => module.ModuleSpec == edge.Target.ModuleSpec));

            Compiled compiledModule;
            if (resolvable.ModuleSpec == moduleSpec) { compiledModule = this; }
            else { compiledModule = resolvable.IntoCompiled(); }

            if (compiledRequirements.Any()) { Graph.AddVerticesAndEdgeRange(compiledRequirements.Select(requirement => new Edge<Compiled>(compiledModule, requirement))); }
            else { Graph.AddVertex(compiledModule); }
        });

        // Iterate over the graph and add the parent-child relationships.
        Graph.Edges.ToList().ForEach(edge =>
        {
            edge.Target.Parents.Add(edge.Source);
        });

        Logger.Trace("Analyzing compiled modules.");
        Graph.Vertices.Where(compiled => compiled is CompiledLocalModule).ToList().ForEach(compiled =>
        {
            var imports = Graph.OutEdges(compiled).Select(edge => edge.Target);
            Analyser.Analyser.Analyse((CompiledLocalModule)compiled, [.. imports]);
        });
    }

    public override string GetPowerShellObject()
    {
        var info = Assembly.GetExecutingAssembly().GetName();
        using var templateStream = Assembly.GetExecutingAssembly().GetManifestResourceStream($"{info.Name}.Resources.ScriptTemplate.ps1")!;
        using var streamReader = new StreamReader(templateStream, Encoding.UTF8);
        var template = streamReader.ReadToEnd();

        var EMBEDDED_MODULES = new StringBuilder();
        EMBEDDED_MODULES.AppendLine("$Script:EMBEDDED_MODULES = @(");
        Graph.Vertices.ToList().ForEach(module =>
        {
            var moduleObject = module switch
            {
                CompiledScript script when script == this => base.GetPowerShellObject(),
                _ => module.GetPowerShellObject()
            };

            var lineCount = moduleObject.Count(character => character == '\n');
            // Only skip the lines of the content of the module object.
            var skipLines = Enumerable.Range(6, lineCount - 6);
            EMBEDDED_MODULES.AppendLine(IndentString(moduleObject, 8, skipLines));
        });
        EMBEDDED_MODULES.AppendLine(IndentString(");", 4));

        var PARAM_BLOCK = new StringBuilder();
        if (ScriptParamBlock != null)
        {
            ScriptParamBlock.Attributes.ToList().ForEach(attribute => PARAM_BLOCK.AppendLine(attribute.Extent.Text));
            PARAM_BLOCK.Append(ScriptParamBlock.Extent.Text);
        }

        var IMPORT_ORDER = Graph.TopologicalSort()
            .Skip(1) // Skip the root node.
            .Reverse()
            .Select(module => $"'{module.GetNameHash()}'")
            .Aggregate((a, b) => $"{a}, {b}");

        // TODO - Implement a way to replace #!DEFINE macros in the template.
        // This could also be how we can implement secure variables during compilation.
        template = template
            .Replace("#!DEFINE EMBEDDED_MODULES", EMBEDDED_MODULES.ToString())
            .Replace("#!DEFINE PARAM_BLOCK", PARAM_BLOCK.ToString())
            .Replace("#!DEFINE IMPORT_ORDER", $"$Script:REMOVE_ORDER = @({IMPORT_ORDER});");

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
    private static string IndentString(string str, int indentBy, IEnumerable<int>? skipLines = null)
    {
        if (!Program.IsDebugging) { return str; }

        var indent = new string(' ', indentBy);
        var lines = str.Split('\n');
        var indentedLines = lines.Select((line, index) =>
        {
            if (string.IsNullOrWhiteSpace(line)) { return line; } // Skip empty lines.
            if (skipLines != null && skipLines.Contains(index)) { return line; }
            return indent + line;
        });

        return string.Join('\n', indentedLines);
    }
}
