// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using C = System.Collections.Generic;
using System.Collections.Concurrent;
using System.Collections.ObjectModel;
using System.Diagnostics.CodeAnalysis;
using Compiler.Module.Compiled;
using Compiler.Requirements;
using LanguageExt;
using NLog;
using QuikGraph;
using QuikGraph.Graphviz;
using System.IO;
using QuikGraph.Graphviz.Dot;
namespace Compiler.Module.Resolvable;

public abstract partial class Resolvable(ModuleSpec moduleSpec) : Module(moduleSpec) {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    /// <summary>
    /// Resolves the requirements of the module.
    /// </summary>
    /// <returns>
    /// None if the requirements were resolved successfully, otherwise an exception.
    /// </returns>
    [return: NotNull]
    public abstract Task<Option<Error>> ResolveRequirements();

    [return: NotNull]
    public abstract Task<Fin<Compiled.Compiled>> IntoCompiled(ResolvableParent resolvableParent);

    /// <summary>
    /// Create an instance of the Resolvable class,
    /// catching exceptions and enriching them with the module spec.
    ///
    /// Will try to create a local module if the parent is a local module,
    /// otherwise it will create a remote module.
    ///
    /// If there is an <see cref="InvalidModulePathError"> while creating the local module it will fall back to a remote module.
    /// </summary>
    /// <param name="parentResolvable"></param>
    /// <param name="moduleSpec"></param>
    /// <param name="mergeWith"></param>
    /// <returns></returns>
    [return: NotNull]
    internal static async Task<Fin<Resolvable>> TryCreate(
        [NotNull] Option<Resolvable> parentResolvable,
        [NotNull] ModuleSpec moduleSpec,
        Collection<ModuleSpec>? mergeWith = default
    ) {
        if (mergeWith is not null && mergeWith.Count != 0) {
            moduleSpec = moduleSpec.MergeSpecs([.. mergeWith]);
        }

        Resolvable? resolvable = null;
        if (parentResolvable.IsSome(out var parent) && parent is ResolvableLocalModule localParent) {
            var parentPath = Path.GetDirectoryName(localParent.ModuleSpec.FullPath)!;
            try {
                var pathedModuleSpec = new PathedModuleSpec(parentPath, moduleSpec.Name);
                resolvable = new ResolvableLocalModule(parentPath, moduleSpec);
            } catch (ExceptionalException err) when (err.ToError() is InvalidModulePathError) {
                // Silent fall through to remote.
            } catch (ExceptionalException err) {
                Logger.Debug("Caught Exceptional with Error type {0}", err.ToError().GetType());
                return err.ToError().Enrich(moduleSpec); // Get the underlying error instead of the wrapped one.
            } catch (Exception err) {
                Logger.Debug($"Caught exception while trying to create local module, {err.GetType()}");
                return (Error)err.Enrich(moduleSpec);
            }
        }

        if (resolvable is null) {
            try {
                resolvable = new ResolvableRemoteModule(moduleSpec);
            } catch (Exception err) {
                return FinFail<Resolvable>(err);
            }
        }

        var requirements = await resolvable.ResolveRequirements();
        return requirements.Match(
            exception => FinFail<Resolvable>(exception.Enrich(moduleSpec)),
            () => FinSucc(resolvable)
        );
    }

    internal static async Task<Fin<ResolvableScript>> TryCreateScript([NotNull] PathedModuleSpec moduleSpec, [NotNull] ResolvableParent parent) {
        try {
            var script = new ResolvableScript(moduleSpec, parent);
            return (await script.ResolveRequirements()).Match(
                exception => FinFail<ResolvableScript>(exception.Enrich(moduleSpec)),
                () => FinSucc(script)
            );
        } catch (Exception err) {
            return FinFail<ResolvableScript>(err);
        }
    }
}

/// <summary>
/// A group of resolvables that can be resolved together.
/// This is useful for resolving a group of modules that have dependencies between each other.
/// While resolving, the resolvables will check for circular dependencies and resolve them in the correct order.
/// </summary>
public class ResolvableParent {
    public record ResolvedMatch(Resolvable Resolvable, ModuleMatch Match);

    public record ResolvableInfo(
        [NotNull] Option<Fin<Compiled.Compiled>> Compiled,
        [NotNull] Option<Action<CompiledScript>> OnCompletion
    );

    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public readonly ConcurrentDictionary<ModuleSpec, ResolvableInfo> Resolvables = [];

    /// <summary>
    /// A graph of resolvable roots and their dependencies.
    /// </summary>
    public readonly BidirectionalGraph<Resolvable, Edge<Resolvable>> Graph = new();

    public readonly string SourceRoot;

    public ResolvableParent([NotNull] string sourceRoot) {
        this.SourceRoot = sourceRoot;

        this.Graph.VertexAdded += vertex => Logger.Debug($"Vertex added: {vertex.ModuleSpec.Name}");
        this.Graph.VertexRemoved += vertex => Logger.Debug($"Vertex removed: {vertex.ModuleSpec.Name}");
        this.Graph.EdgeRemoved += edge => {
            Logger.Debug($"Edge removed: {edge.Source.ModuleSpec.Name} -> {edge.Target.ModuleSpec.Name}");
            lock (edge.Source.Requirements) {
                edge.Source.Requirements.RemoveRequirement(edge.Target.ModuleSpec);
            }
        };
        this.Graph.EdgeAdded += edge => {
            Logger.Debug($"Edge added: {edge.Source.ModuleSpec.Name} -> {edge.Target.ModuleSpec.Name}");
            lock (edge.Source.Requirements) {
                edge.Source.Requirements.AddRequirement(edge.Target.ModuleSpec);
            }
        };
    }

    public BidirectionalGraph<Resolvable, Edge<Resolvable>> GetGraphFromRoot(Resolvable resolvable) {
        var graph = new BidirectionalGraph<Resolvable, Edge<Resolvable>>();
        graph.AddVertex(resolvable);

        var processedAsRoot = new C.HashSet<Resolvable>();
        var iterating = new Queue<Resolvable>([resolvable]);
        do {
            var currentResolvable = iterating.Dequeue();
            lock (this.Graph) {
                // Skip if we've already processed a vertex like this
                if (processedAsRoot.Contains(currentResolvable)) continue;

                this.Graph.TryGetOutEdges(currentResolvable, out var outEdges);
                outEdges.ToList().ForEach(edge => {
                    graph.AddVerticesAndEdge(edge);
                    iterating.Enqueue(edge.Target);
                });
                processedAsRoot.Add(currentResolvable);
            }
        } while (iterating.Count > 0);

        return graph;
    }

    public void QueueResolve([NotNull] Resolvable rootModule, Action<CompiledScript>? onCompletion = null) {
        lock (this.Graph) {
            this.Graph.AddVertex(rootModule);
        }

        this.Resolvables.TryAdd(rootModule.ModuleSpec, new(None, onCompletion.AsOption()));
    }

    /// <summary>
    /// Locates a module which matches the given spec within the group.
    /// </summary>
    /// <param name="moduleSpec"></param>
    /// <returns></returns>
    public Option<ResolvedMatch> FindResolvable([NotNull] ModuleSpec moduleSpec) =>
        (from resolvable in this.Graph.Vertices
         where resolvable.ModuleSpec.CompareTo(moduleSpec) != ModuleMatch.None
         select new ResolvedMatch(resolvable, resolvable.ModuleSpec.CompareTo(moduleSpec))
        ).FirstOrDefault();

    public async Task Compile() {
        await this.ResolveDepedencyGraph();
        this.DebugGraphAtPoint();

        var graph = this.Graph.Clone();
        while (graph.Vertices.Any()) {
            var nextBatch = from r in graph.Vertices
                            where !graph.TryGetOutEdges(r, out var outEdges) || !outEdges.Any()
                            select r;

            Logger.Debug($"Compiling batch of {nextBatch.Count()} modules: {string.Join(", ", nextBatch.Select(r => r.ModuleSpec.Name))}");

            if (!nextBatch.Any()) {
                // No progress can be made, but we haven't compiled everything
                // This means we have a cycle in the dependency graph
                var remaining = from r in graph.Vertices
                                select r.ModuleSpec.ToString();

                Logger.Error($"Dependency cycle detected! Cannot compile: {string.Join(", ", remaining)}");
                throw new InvalidOperationException("Dependency cycle detected in the compilation graph");
            }

            var compileTasks = from mod in nextBatch
                               select Task.Run(async () => {
                                   try {
                                       var result = await mod.IntoCompiled(this);
                                       if (result.IsOk(out var compiled, out var _)) {
                                           this.OnCompiledModule(mod.ModuleSpec, compiled);
                                       }
                                       return result;
                                   } catch (Exception ex) {
                                       Logger.Error(ex, $"Error compiling {mod.ModuleSpec}");
                                       throw;
                                   }
                               });

            await Task.WhenAll(compileTasks);
            nextBatch.ToList().ForEach(mod => graph.RemoveVertex(mod));
        }

        var completionTasks = from resolvable in this.Resolvables.Values
                              where resolvable.Compiled.IsSome
                              let compiled = resolvable.Compiled.Unwrap().Unwrap()
                              select Task.Run(() => {
                                  compiled.CompleteCompileAfterResolution();
                                  resolvable.OnCompletion.IfSome(onComplete => {
                                      if (compiled is CompiledScript script) {
                                          onComplete(script);
                                      }
                                  });
                              });
        await Task.WhenAll(completionTasks);
    }

    private void OnCompiledModule(ModuleSpec moduleSpec, Compiled.Compiled compiled) {
        if (this.Resolvables.TryGetValue(moduleSpec, out var info)) {
            this.Resolvables.TryUpdate(
                moduleSpec,
                info with {
                    Compiled = FinSucc(compiled),
                },
                info
            );
        } else {
            Logger.Warn($"Compiled module {moduleSpec.Name} but no resolvable info was found");
            this.Resolvables[moduleSpec] = new ResolvableInfo(
                FinSucc(compiled),
                None
            );
        }
    }

    /// <summary>
    /// Creates all the links between the modules and their dependencies.
    /// </summary>
    private async Task ResolveDepedencyGraph() {
        Queue<(Resolvable?, ModuleSpec)> iterating;
        lock (this.Graph) {
            iterating = new(this.Graph.Vertices.Select(res => ((Resolvable?)null, res.ModuleSpec)));
        }

        var runningTasks = new List<(ModuleSpec Key, Task Task)>();
        do {
            if (iterating.TryDequeue(out var item)) {
                var (parentResolvable, workingModuleSpec) = item;
                runningTasks.Add((workingModuleSpec, Task.Run(async () => {
                    // If the parent module has already been resolved this will be an orphan.
                    if (parentResolvable != null && !this.Graph.ContainsVertex(parentResolvable)) {
                        Logger.Debug("Parent module had already been resolved, skipping orphan.");
                        return;
                    }

                    var resolvableResult = await this.LinkFindingPossibleResolved(parentResolvable, workingModuleSpec);

                    Option<Resolvable> workingResolvable = None;
                    if (resolvableResult.IsErr(out var err, out workingResolvable)) {
                        Logger.Error($"Failed to link {workingModuleSpec} to {parentResolvable?.ModuleSpec}.");
                        Program.Errors.Add(err);
                        return;
                    }

                    // If it was null or there are out edges it means this module has already been resolved.
                    if (!workingResolvable.IsSome(out var safeWorkingResolvable)
                        || (this.Graph.TryGetOutEdges(safeWorkingResolvable, out var outEdges) && outEdges.Any())) {
                        return;
                    }

                    lock (safeWorkingResolvable.Requirements) {
                        safeWorkingResolvable.Requirements.GetRequirements<ModuleSpec>().ToList()
                            .ForEach(requirement => iterating.Enqueue((safeWorkingResolvable, requirement)));
                    }
                })));
            }

            runningTasks.RemoveAll(task => task.Task.IsCompleted);

            if (runningTasks.Count != 0) {
                Logger.Debug($"Waiting for tasks to complete, {runningTasks.Count} running with {iterating.Count} left to process.");
                await Task.WhenAny(runningTasks.Select(task => task.Task));
            }
        } while (iterating.Count != 0 || runningTasks.Count != 0);

        Logger.Debug("Finished resolving all modules.");
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
    [return: NotNull]
    public async Task<Fin<Option<Resolvable>>> LinkFindingPossibleResolved(
        Resolvable? parentResolvable,
        [NotNull] ModuleSpec moduleToResolve
    ) {
        ArgumentNullException.ThrowIfNull(moduleToResolve);

        Resolvable? resultingResolvable = null;
        Resolvable? foundResolvable = null;
        var match = ModuleMatch.None;
        this.FindResolvable(moduleToResolve).IfSome(resolvableMatch => {
            resolvableMatch.Deconstruct(out foundResolvable, out match);
            DebugVisualizeLinkAttempt(parentResolvable, moduleToResolve, match, foundResolvable, $"Found: {foundResolvable.ModuleSpec.Name}");
        });

        if (foundResolvable is not null) {
            Logger.Debug($"Found existing resolvable for {moduleToResolve.Name} with match: {match}");

            switch (match) {
                case ModuleMatch.PreferOurs or ModuleMatch.Same:
                    resultingResolvable = foundResolvable;
                    break;
                case ModuleMatch.Incompatible:
                    Logger.Error($"⚠️ Incompatible module versions found for {moduleToResolve.Name}");
                    return FinFail<Option<Resolvable>>(Error.New($"Incompatible module versions found for {moduleToResolve.Name}."));
                case ModuleMatch.MergeRequired or ModuleMatch.Stricter or ModuleMatch.Looser:
                    var (mergeFrom, mergeWith) = match switch {
                        ModuleMatch.MergeRequired => (moduleToResolve, new List<ModuleSpec> { foundResolvable.ModuleSpec }),
                        ModuleMatch.Stricter or ModuleMatch.Looser => (foundResolvable.ModuleSpec, [moduleToResolve]),
                        _ => (moduleToResolve, []),
                    };

                    Logger.Debug($"Merging modules: {mergeFrom.Name} with {string.Join(", ", mergeWith.Select(m => m.Name))}");

                    var fin = await Resolvable.TryCreate(
                        parentResolvable.AsOption(),
                        mergeFrom,
                        [.. mergeWith]
                    );

                    if (fin.IsErr(out var err, out var resolvable) && err is InvalidModulePathError) {
                        Logger.Debug($"Failed to find local module {moduleToResolve.Name}, trying remote.");
                    } else if (err is not null) {
                        Logger.Error($"⚠️ Error creating resolvable for {moduleToResolve.Name}: {err}");
                        return FinFail<Option<Resolvable>>(err);
                    } else {
                        resultingResolvable = resolvable;
                        Logger.Debug($"Successfully created merged resolvable for {moduleToResolve.Name}");
                    }

                    break;
                case ModuleMatch.None or ModuleMatch.PreferTheirs or ModuleMatch.Looser:
                    goto default;
                default:
                    break;
            }

            if (resultingResolvable is null) {
                return FinFail<Option<Resolvable>>(Error.New($"Failed to resolve {moduleToResolve.Name}."));
            }

            // Propogate the merge if the module isn't the same.
            if (!ReferenceEquals(foundResolvable, resultingResolvable)) {
                Logger.Debug($"Propogating merge of {foundResolvable.ModuleSpec} with {moduleToResolve}, resulting in {resultingResolvable.ModuleSpec}.");

                this.Graph.TryGetInEdges(foundResolvable, out var inEdges);
                this.Graph.TryGetOutEdges(foundResolvable, out var outEdges);

                inEdges.ToList().ForEach(edge => {
                    this.Graph.AddVerticesAndEdge(new Edge<Resolvable>(edge.Source, resultingResolvable));
                    this.Graph.RemoveEdge(edge);
                });
                outEdges.ToList().ForEach(edge => {
                    this.Graph.AddVerticesAndEdge(new Edge<Resolvable>(resultingResolvable, edge.Target));
                    this.Graph.RemoveEdge(edge);
                });

                this.Graph.RemoveVertex(foundResolvable);

                if (this.Resolvables.Remove(foundResolvable.ModuleSpec, out var resolvableInfo)) {
                    this.Resolvables[resultingResolvable.ModuleSpec] = resolvableInfo;
                }
            }
        } else {
            Logger.Debug($"No existing resolvable found for {moduleToResolve.Name}, creating new one");
            var newResolvable = await Resolvable.TryCreate(parentResolvable.AsOption(), moduleToResolve);
            if (newResolvable.IsErr(out var err, out resultingResolvable)) {
                Logger.Error($"⚠️ Failed to create resolvable for {moduleToResolve.Name}: {err}");
                return FinFail<Option<Resolvable>>(err);
            }
            Logger.Debug($"Successfully created new resolvable for {moduleToResolve.Name}");
        }

        lock (this.Graph) {
            if (parentResolvable != null) {
                if (this.Graph.Edges.Any(edge => edge.Source == parentResolvable && edge.Target == resultingResolvable)) {
                    Logger.Debug("Edge already exists, skipping.");
                    return FinSucc<Option<Resolvable>>(None);
                }

                lock (parentResolvable.Requirements) {
                    if (!parentResolvable.Requirements.RemoveRequirement(moduleToResolve))
                        Logger.Warn($"Failed to remove requirement {moduleToResolve} from {parentResolvable.ModuleSpec}.");
                }
                this.Graph.AddVerticesAndEdge(new Edge<Resolvable>(parentResolvable, resultingResolvable));
            } else {
                Logger.Debug($"Adding vertex: {resultingResolvable.ModuleSpec.Name}");
                this.Graph.AddVertex(resultingResolvable);
            }
        }

        this.Resolvables.TryAdd(resultingResolvable.ModuleSpec, new(None, None));

        return FinSucc(Some(resultingResolvable));
    }

    public static void DebugVisualizeLinkAttempt(
        Resolvable? parentResolvable,
        ModuleSpec moduleToResolve,
        ModuleMatch match = ModuleMatch.None,
        Resolvable? foundResolvable = null,
        string message = ""
    ) {
        if (!Program.IsDebugging) return;

        Logger.Debug($"🔗 LINK ATTEMPT: {parentResolvable?.ModuleSpec.Name ?? "Root"} -> {moduleToResolve.Name} ({match}) {message}");

        // Create a visualization of just this link
        var tempGraph = new BidirectionalGraph<Resolvable, Edge<Resolvable>>();

        if (parentResolvable != null) {
            tempGraph.AddVertex(parentResolvable);
        }

        if (foundResolvable != null) {
            tempGraph.AddVertex(foundResolvable);
            if (parentResolvable != null) {
                tempGraph.AddEdge(new Edge<Resolvable>(parentResolvable, foundResolvable));
            }
        }

        var dotGraph = tempGraph.ToGraphviz(alg => {
            alg.FormatVertex += (sender, args) => {
                var color = GraphvizColor.Black;
                if (ReferenceEquals(args.Vertex, parentResolvable)) color = GraphvizColor.Blue;
                if (ReferenceEquals(args.Vertex, foundResolvable)) color = GraphvizColor.Green;

                args.VertexFormat.Label = args.Vertex.ModuleSpec.Name;
                args.VertexFormat.FontColor = color;
                args.VertexFormat.StrokeColor = color;
            };
        });

        Logger.Debug($"Link visualization:\n{dotGraph}");
    }

    public void DebugGraphAtPoint() {
        if (!Program.IsDebugging) return;

        var dotGraph = this.Graph.ToGraphviz(alg => {
            alg.FormatVertex += (sender, args) => {
                args.VertexFormat.Label = args.Vertex.ModuleSpec.Name;
                args.VertexFormat.Comment = args.Vertex.ModuleSpec.ToString();
            };
        });

        Logger.Debug($"Graph: \n{dotGraph}");
    }
}
