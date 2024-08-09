using Compiler.Requirements;
using NLog;
using QuikGraph;

namespace Compiler.Module.Resolvable;

public abstract partial class Resolvable(ModuleSpec moduleSpec) : Module(moduleSpec)
{
    /// <summary>
    /// Resolves the requirements of the module.
    /// </summary>
    public abstract void ResolveRequirements();

    public abstract Compiled.Compiled IntoCompiled();
}

/// <summary>
/// A group of resolvables that can be resolved together.
/// This is useful for resolving a group of modules that have dependencies between each other.
/// While resolving, the resolvables will check for circular dependencies and resolve them in the correct order.
/// </summary>
public class ResolvableParent
{
    public record ResolvedMatch(Resolvable Resolvable, ModuleMatch Match);

    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public readonly BidirectionalGraph<Resolvable, Edge<Resolvable>> Graph;

    public ResolvableParent(Resolvable rootModule)
    {
        Graph = new BidirectionalGraph<Resolvable, Edge<Resolvable>>();
        Graph.AddVertex(rootModule);

        #region Deduplication and merging of Resolvables using events
        Graph.VertexAdded += vertex => Logger.Debug($"Vertex added: {vertex.ModuleSpec.Name}");
        Graph.VertexRemoved += vertex => Logger.Debug($"Vertex removed: {vertex.ModuleSpec.Name}");
        Graph.EdgeRemoved += edge =>
        {
            Logger.Debug($"Edge removed: {edge.Source.ModuleSpec.Name} -> {edge.Target.ModuleSpec.Name}");
            lock (edge.Source.Requirements)
            {
                var didRemove = edge.Source.Requirements.RemoveRequirement(edge.Target.ModuleSpec);
                if (!didRemove) Logger.Warn($"Failed to remove requirement {edge.Target.ModuleSpec} from {edge.Source.ModuleSpec}.");
            }
        };
        Graph.EdgeAdded += edge =>
        {
            Logger.Debug($"Edge added: {edge.Source.ModuleSpec.Name} -> {edge.Target.ModuleSpec.Name}");
            lock (edge.Source.Requirements)
            {
                var didAdd = edge.Source.Requirements.AddRequirement(edge.Target.ModuleSpec);
                if (!didAdd) Logger.Warn($"Failed to add requirement {edge.Target.ModuleSpec} to {edge.Source.ModuleSpec}.");
            }
        };
        #endregion
    }

    /// <summary>
    /// Locates a module which matches the given spec within the group.
    /// </summary>
    /// <param name="moduleSpec"></param>
    /// <returns></returns>
    public ResolvedMatch? FindResolvable(ModuleSpec moduleSpec)
    {
        var resolvable = Graph.Vertices.FirstOrDefault(resolvable => resolvable.ModuleSpec.CompareTo(moduleSpec) != ModuleMatch.None);
        if (resolvable == null) return null;

        return new(resolvable, resolvable.ModuleSpec.CompareTo(moduleSpec));
    }

    public void Resolve()
    {
        lock (Graph)
        {
            var iterating = new Queue<(Resolvable?, ModuleSpec)>(Graph.Vertices.Select(resolvable => ((Resolvable?)null, resolvable.ModuleSpec)));
            do
            {
                var (parentResolvable, workingModuleSpec) = iterating.Dequeue();
                Logger.Trace($"Resolving {workingModuleSpec} with parent {parentResolvable?.ModuleSpec}.");

                // If the parent module has already been resolved this will be an orphan.
                if (parentResolvable != null && !Graph.ContainsVertex(parentResolvable))
                {
                    Logger.Debug("Parent module had already been resolved, skipping orphan.");
                    continue;
                }

                var workingResolvable = LinkFindingPossibleResolved(parentResolvable, workingModuleSpec);

                // If it was null or there are out edges it means this module has already been resolved.
                if (workingResolvable == null || Graph.TryGetOutEdges(workingResolvable, out var outEdges) && outEdges.Any())
                {
                    Logger.Debug("Module has already been resolved, skipping.");
                    continue;
                }

                lock (workingResolvable.Requirements)
                {
                    workingResolvable.Requirements.GetRequirements<ModuleSpec>().ToList().ForEach(requirement => iterating.Enqueue((workingResolvable, requirement)));
                }
            } while (iterating.Count > 0);
        }
    }

    /// <summary>
    /// Links a module to a new ModuleSpec, if the module has already been resolved it will return the resolved module.
    ///
    /// If the resolved module is a looser match it will merge the requirements and return the new module, updating the graph.
    /// </summary>
    /// <param name="parentResolvable">
    /// The parent which is trying to resolve the module.
    /// </param>
    /// <param name="moduleToResolve">
    /// The module to resolve.
    /// </param>
    /// <returns>
    /// The resolved module.
    ///
    /// Returns null if the module was already resolved.
    /// </returns>
    /// <exception cref="Exception">
    /// If the module is incompatible with the current module.
    /// </exception>
    public Resolvable? LinkFindingPossibleResolved(
        Resolvable? parentResolvable,
        ModuleSpec moduleToResolve)
    {
        var resolveableMatch = FindResolvable(moduleToResolve);
        Resolvable? resultingResolvable = null;
        if (resolveableMatch != null)
        {
            Logger.Debug($"Found existing resolvable for {moduleToResolve.Name}.");

            resolveableMatch.Deconstruct(out var foundResolvable, out var match);
            // If the module is not a same match we need to merge and propagate the requirements.
            // If its an incompatible match we need to throw an error.
            resultingResolvable = match switch
            {
                ModuleMatch.PreferOurs or ModuleMatch.Same or ModuleMatch.Looser => foundResolvable,
                ModuleMatch.MergeRequired or ModuleMatch.Stricter => foundResolvable switch
                {
                    ResolvableLocalModule local => new ResolvableLocalModule(Path.GetDirectoryName(local.ModuleSpec.FullPath)!, moduleToResolve.MergeSpecs([foundResolvable.ModuleSpec])),
                    _ => new ResolvableRemoteModule(moduleToResolve.MergeSpecs([foundResolvable.ModuleSpec]))
                },
                ModuleMatch.Incompatible => throw new Exception($"Incompatible module versions found for {moduleToResolve.Name}."),
                _ => throw new Exception("This should never happen.")
            };

            // Propogate the merge if the module isn't the same.
            if (!ReferenceEquals(foundResolvable, resultingResolvable))
            {
                Logger.Debug($"Propogating merge of {foundResolvable.ModuleSpec} with {moduleToResolve}, resulting in {resultingResolvable.ModuleSpec}.");

                Graph.TryGetInEdges(foundResolvable, out var inEdges);
                Graph.TryGetOutEdges(foundResolvable, out var outEdges);

                if (!Graph.RemoveVertex(foundResolvable)) Logger.Warn($"Failed to remove vertex {foundResolvable.ModuleSpec}.");
                inEdges.ToList().ForEach(edge => Graph.AddVerticesAndEdge(new Edge<Resolvable>(edge.Source, resultingResolvable)));
                outEdges.ToList().ForEach(edge => Graph.AddVerticesAndEdge(new Edge<Resolvable>(resultingResolvable, edge.Target)));
            }
        }
        else
        {
            if (parentResolvable is ResolvableLocalModule local)
            {
                try { resultingResolvable = new ResolvableLocalModule(Path.GetDirectoryName(local.ModuleSpec.FullPath)!, moduleToResolve); }
                catch { /*This just happens when its not a file and might actually be a remote module*/ }
            }
            resultingResolvable ??= new ResolvableRemoteModule(moduleToResolve);
        }

        if (parentResolvable != null)
        {
            if (Graph.Edges.Where(edge => edge.Source == parentResolvable && edge.Target == resultingResolvable).Any())
            {
                Logger.Debug("Edge already exists, skipping.");
                return null;
            }

            lock (parentResolvable.Requirements)
            {
                if (!parentResolvable.Requirements.RemoveRequirement(moduleToResolve)) Logger.Warn($"Failed to remove requirement {moduleToResolve} from {parentResolvable.ModuleSpec}.");
            }
            Graph.AddVerticesAndEdge(new Edge<Resolvable>(parentResolvable, resultingResolvable));
        }
        else { Graph.AddVertex(resultingResolvable); }

        return resultingResolvable;
    }
}
