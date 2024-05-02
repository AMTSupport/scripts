using System.Security.Cryptography;
using Compiler;
using Compiler.Module;
using QuikGraph;

class CompiledScript : LocalFileModule
{
    public readonly AdjacencyGraph<ModuleSpec, Edge<ModuleSpec>> ModuleGraph = new();
    public readonly Dictionary<string, Module> ResolvedModules = [];

    public CompiledScript(string name, string[] lines) : base(name, lines)
    {

        foreach (var module in Requirements.GetRequirements<ModuleSpec>())
        {
            ModuleGraph.AddEdge(new Edge<ModuleSpec>(ModuleSpec, module));
        }

        ResolveRequirements();
    }

    private void ResolveRequirements()
    {
        var localModules = new List<LocalFileModule>();
        var downloadableModules = new List<RemoteModule>();

        var iterating = new Queue<ModuleSpec>([ModuleSpec]);
        while (iterating.TryDequeue(out ModuleSpec? current) && current != null)
        {
            if (localModules.Any(module => module.GetModuleMatchFor(current) == ModuleMatch.Exact) || downloadableModules.Any(module => module.GetModuleMatchFor(current) == ModuleMatch.Exact))
            {
                continue;
            }

            if (!ModuleGraph.ContainsVertex(current))
            {
                ModuleGraph.AddVertex(current);
            }

            ModuleGraph.AddEdge(new Edge<ModuleSpec>(ModuleSpec, current));

            var resolvedPath = Path.GetFullPath(current.Name);
            if (File.Exists(resolvedPath))
            {
                var localModule = LocalFileModule.FromFile(current.Name);
                localModules.Add(localModule);

                localModule.Requirements.GetRequirements<ModuleSpec>().ForEach(module =>
                {
                    ModuleGraph.AddEdge(new Edge<ModuleSpec>(current, module));
                    iterating.Enqueue(module);
                });

                continue;
            }

            var downloadableModule = RemoteModule.FromModuleRequirement(current);
            downloadableModules.Add(downloadableModule);
        }

        localModules.ForEach(module =>
        {
            ResolvedModules.Add(module.Name, module);
        });

        foreach (var module in downloadableModules)
        {
            if (!ResolvedModules.TryGetValue(module.Name, out Module? value))
            {
                ResolvedModules.Add(module.Name, module);
                continue;
            }

            var existingModule = value;
            if (existingModule.Version < module.Version)
            {
                ResolvedModules[module.Name] = module;
            }
        }
    }
}
