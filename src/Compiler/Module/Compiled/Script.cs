using System.Management.Automation.Language;
using System.Reflection;
using System.Text;
using Compiler.Analyser;
using Compiler.Module.Resolvable;
using Compiler.Requirements;
using Compiler.Text;
using NLog;
using QuikGraph;
using QuikGraph.Algorithms;
using QuikGraph.Graphviz;

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
        ParamBlockAst? scriptParamBlock
    ) : base(moduleSpec, CompiledDocument.FromBuilder(editor, 0))
    {
        var graphviz = resolvableParent.Graph.ToGraphviz(alg =>
        {
            alg.FormatVertex += (sender, args) =>
            {
                args.VertexFormat.Label = args.Vertex.ModuleSpec.Name;
            };
        });
        Logger.Debug("Initial graphviz:");
        Logger.Debug(graphviz);

        ScriptParamBlock = scriptParamBlock;
        Graph = new BidirectionalGraph<Compiled, Edge<Compiled>>();
        Graph.AddVertex(this);

        Graph.VertexAdded += vertex => Logger.Debug($"Vertex added: {vertex.ModuleSpec.Name}");
        Graph.VertexRemoved += vertex => Logger.Debug($"Vertex removed: {vertex.ModuleSpec.Name}");
        Graph.EdgeAdded += edge => Logger.Debug($"Edge added: {edge.Source.ModuleSpec.Name} -> {edge.Target.ModuleSpec.Name}");
        Graph.EdgeRemoved += edge => Logger.Debug($"Edge removed: {edge.Source.ModuleSpec.Name} -> {edge.Target.ModuleSpec.Name}");

        var loadOrder = resolvableParent.Graph.TopologicalSort();
        var reversedLoadOrder = loadOrder.Reverse();
        reversedLoadOrder.ToList().ForEach(resolvable =>
        {
            Logger.Trace($"Compiling {resolvable.ModuleSpec.Name}");

            var compiledRequirements = resolvableParent.Graph
                .OutEdges(resolvable)
                .AsParallel()
                .Select(edge =>
                {
                    try
                    {
                        Logger.Trace($"Getting compiled module for {edge.Target.ModuleSpec}");
                        return Graph.Vertices.First(module => module.ModuleSpec == edge.Target.ModuleSpec);
                    }
                    catch
                    {
                        Logger.Trace($"Could not find module from edge {edge.Target.ModuleSpec}");
                        throw;
                    }
                });

            Compiled compiledModule;
            if (resolvable.ModuleSpec == moduleSpec) { compiledModule = this; }
            else { compiledModule = resolvable.IntoCompiled(); }

            if (compiledRequirements.Any()) { Graph.AddVerticesAndEdgeRange(compiledRequirements.Select(requirement => new Edge<Compiled>(compiledModule, requirement))); }
            else { Graph.AddVertex(compiledModule); }
        });

        graphviz = Graph.ToGraphviz(alg =>
        {
            alg.FormatVertex += (sender, args) =>
            {
                args.VertexFormat.Label = args.Vertex.ModuleSpec.Name;
            };
        });
        Logger.Debug("Compiled graphviz:");
        Logger.Debug(graphviz);

        Logger.Trace("Analyzing compiled modules.");
        Graph.Vertices.Where(compiled => compiled is CompiledLocalModule).ToList().ForEach(compiled =>
        {
            var imports = Graph.OutEdges(compiled).Select(edge => edge.Target);
            StaticAnalyser.Analyse((CompiledLocalModule)compiled, [.. imports]);
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

        // TODO - Implement a way to replace #!DEFINE macros in the template.
        // This could also be how we can implement secure variables during compilation.
        template = template.Replace("#!DEFINE EMBEDDED_MODULES", EMBEDDED_MODULES.ToString());
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
