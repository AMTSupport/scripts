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
    public abstract Task<Fin<Compiled.Compiled>> IntoCompiled();

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
                Logger.Debug($"Looking for {moduleSpec.Name} module in {parentPath}.");
                resolvable = new ResolvableLocalModule(parentPath, moduleSpec);
            } catch (ExceptionalException err) when (err.ToError() is InvalidModulePathError) {
                // Silent fall through to remote.
            } catch (ExceptionalException err) {
                Logger.Debug("Caught Exceptional with Error type {0}", err.ToError().GetType());
                return FinFail<Resolvable>(err.Enrich(moduleSpec));
            } catch (Exception err) {
                Logger.Debug($"Caught exception while trying to create local module, {err.GetType()}");
                return FinFail<Resolvable>(err.Enrich(moduleSpec));
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
        [NotNull] Option<Action<CompiledScript>> OnCompletion,
        [NotNull] Option<Task<Fin<Compiled.Compiled>>> CompilingTask
    );

    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private readonly List<(ModuleSpec, Task)> RunningTasks = [];

    public readonly Dictionary<ModuleSpec, ResolvableInfo> Resolvables = [];

    /// <summary>
    /// A graph of resolvable roots and their dependencies.
    /// </summary>
    public readonly BidirectionalGraph<Resolvable, Edge<Resolvable>> Graph = new();

    public ResolvableParent() {
        #region Deduplication and merging of Resolvables using events
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
        #endregion
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

        lock (this.Resolvables) {
            this.Resolvables[rootModule.ModuleSpec] = new(None, onCompletion.AsOption(), None);
        }
    }

    /// <summary>
    /// Locates a module which matches the given spec within the group.
    /// </summary>
    /// <param name="moduleSpec"></param>
    /// <returns></returns>
    public async Task<Option<ResolvedMatch>> FindResolvable([NotNull] ModuleSpec moduleSpec) {
        var resolvable = this.Graph.Vertices
            .FirstOrDefault(resolvable => resolvable.ModuleSpec.CompareTo(moduleSpec) != ModuleMatch.None);

        var fromRunningTask = this.RunningTasks
            .Where(task => !ReferenceEquals(task.Item1, moduleSpec))
            .FirstOrDefault(task => task.Item1.CompareTo(moduleSpec) != ModuleMatch.None);

        if (resolvable is not null) {
            return new ResolvedMatch(resolvable, resolvable.ModuleSpec.CompareTo(moduleSpec));
        } else if (fromRunningTask.Item1 is not null) {
            Logger.Debug($"{moduleSpec} is waiting for {fromRunningTask.Item1} to complete.");
            await fromRunningTask.Item2;
            var awaitedResolvable = this.Graph.Vertices.FirstOrDefault(resolvable => ReferenceEquals(fromRunningTask.Item1, resolvable.ModuleSpec))!;
            return new ResolvedMatch(awaitedResolvable, fromRunningTask.Item1.CompareTo(moduleSpec));
        }

        return None;
    }

    public async Task<Fin<Compiled.Compiled>> WaitForCompiled(ModuleSpec moduleSpec) {
        if (this.RunningTasks.Count > 0) {
            await Task.WhenAll(this.RunningTasks.Select(task => task.Item2));
        }

        var resolvable = this.Graph.Vertices.FirstOrDefault(res => res.ModuleSpec == moduleSpec);
        if (resolvable is null) {
            return FinFail<Compiled.Compiled>(Error.New($"No resolvable found for {moduleSpec}."));
        }

        if (!this.Resolvables.TryGetValue(moduleSpec, out var resolvableInfo)) {
            return FinFail<Compiled.Compiled>(Error.New($"No resolvable info found for {moduleSpec}."));
        }

        var (compiledOpt, onCompletion, waitHandle) = resolvableInfo;
        if (compiledOpt.IsSome(out var compiledFin)) {
            if (compiledFin.IsErr(out var err, out var compiled)) {
                return FinFail<Compiled.Compiled>(err);
            }

            return FinSucc(compiled);
        }

        // if the compiled is none and the error is none then we need to wait for the wait handle if it exists,
        // otherwise we need to start the compilation.
        if (waitHandle.IsSome(out var runningTask)) {
            return await runningTask;
        } else {
            var compilingTask = Task.Run(async () => {
                var newlyCompiledModule = await resolvable.IntoCompiled();

                lock (this.Resolvables) {
                    this.Resolvables[moduleSpec] = resolvableInfo with {
                        Compiled = newlyCompiledModule
                    };
                }

                newlyCompiledModule.IfSucc(module => onCompletion.IfSome(
                    onCompletion => onCompletion((module as CompiledScript)!) // Safety: We know it's a compiled script
                ));

                return newlyCompiledModule;
            });

            lock (this.Resolvables) {
                this.Resolvables[moduleSpec] = resolvableInfo with {
                    CompilingTask = compilingTask
                };
            }

            return await compilingTask;
        }
    }

    public async Task StartCompilation() {
        await this.ResolveDepedencyGraph();

        // Get a list of the scripts which are roots and have no scripts depending on them.
        var topLevelScripts = new Queue<Resolvable>(this.Graph.Vertices.Where(resolvable => !this.Graph.TryGetInEdges(resolvable, out var inEdges) || !inEdges.Any()));
        var compileTasks = new List<Task>();
        foreach (var resolvable in topLevelScripts) {
            compileTasks.Add(Task.Run(async () => {
                Logger.Trace($"Compiling top level script {resolvable.ModuleSpec.Name}");

                var compiledModule = await this.WaitForCompiled(resolvable.ModuleSpec);
                compiledModule.IfFail(err => Program.Errors.Add(err.Enrich(resolvable.ModuleSpec)));
                Logger.Trace($"Finished compiling top level script {resolvable.ModuleSpec.Name}");
            }).ContinueWith(task => {
                if (task.IsFaulted) {
                    Logger.Error(task.Exception, "Failed to compile top level script.");
                    Program.Errors.Add(task.Exception);
                }
            }));
        }

        while (compileTasks.Count > 0) {
            var task = await Task.WhenAny(compileTasks);
            Logger.Debug($"Task completed, {compileTasks.Count} remaining.");
            compileTasks.Remove(task);
        }

        Logger.Trace("Finished compiling all top level scripts.");
    }

    /// <summary>
    /// Creates all the links between the modules and their dependencies.
    /// </summary>
    private async Task ResolveDepedencyGraph() {
        var iterating = new ConcurrentQueue<(Resolvable?, ModuleSpec)>(this.Graph.Vertices.Select(resolvable => ((Resolvable?)null, resolvable.ModuleSpec)));
        do {
            if (iterating.TryDequeue(out var item)) {
                var (parentResolvable, workingModuleSpec) = item;
                var alreadyBeingProcessed = this.RunningTasks.Any(task => task.Item1 == workingModuleSpec);

                this.RunningTasks.Add((workingModuleSpec, Task.Run(async () => {
                    Logger.Trace($"Resolving {workingModuleSpec} with parent {parentResolvable?.ModuleSpec}.");

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
                    if (!workingResolvable.IsSome(out var safeWorkingResolvable) || (this.Graph.TryGetOutEdges(safeWorkingResolvable, out var outEdges) && outEdges.Any())) {
                        Logger.Debug("Module has already been resolved, skipping.");
                        return;
                    }

                    lock (safeWorkingResolvable.Requirements) {
                        safeWorkingResolvable.Requirements.GetRequirements<ModuleSpec>().ToList()
                            .ForEach(requirement => iterating.Enqueue((safeWorkingResolvable, requirement)));
                    }
                })));
            }

            this.RunningTasks.RemoveAll(task => task.Item2.IsCompleted);

            if (this.RunningTasks.Count > 0) {
                Logger.Debug($"Waiting for tasks to complete, {this.RunningTasks.Count} running with {iterating.Count} left to process.");
                await Task.WhenAny(this.RunningTasks.Select(task => task.Item2));
            }
        } while (!iterating.IsEmpty || this.RunningTasks.Count > 0);

        Logger.Debug("Finished resolving all modules.");

        var dotGraph = this.Graph.ToGraphviz(alg => {
            alg.FormatVertex += (sender, args) => {
                args.VertexFormat.Label = args.Vertex.ModuleSpec.Name;
            };
        });
        Console.WriteLine(dotGraph);
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
        (await this.FindResolvable(moduleToResolve)).IfSome(resolvableMatch => {
            resolvableMatch.Deconstruct(out foundResolvable, out match);
        });

        if (foundResolvable is not null) {
            Logger.Debug($"Found existing resolvable for {moduleToResolve.Name}.");

            switch (match) {
                case ModuleMatch.PreferOurs or ModuleMatch.Same or ModuleMatch.Looser:
                    resultingResolvable = foundResolvable;
                    break;
                case ModuleMatch.Incompatible:
                    return FinFail<Option<Resolvable>>(Error.New($"Incompatible module versions found for {moduleToResolve.Name}."));
                case ModuleMatch.MergeRequired or ModuleMatch.Stricter:
                    var (mergeFrom, mergeWith) = match switch {
                        ModuleMatch.MergeRequired => (moduleToResolve, new List<ModuleSpec> { foundResolvable.ModuleSpec }),
                        ModuleMatch.Stricter => (foundResolvable.ModuleSpec, [moduleToResolve]),
                        _ => (moduleToResolve, []),
                    };

                    var fin = await Resolvable.TryCreate(
                        parentResolvable.AsOption(),
                        mergeFrom,
                        [.. mergeWith]
                    );

                    if (fin.IsErr(out var err, out var resolvable) && err is InvalidModulePathError) {
                        Logger.Debug($"Failed to find local module {moduleToResolve.Name}, trying remote.");
                    } else if (err is not null) {
                        return FinFail<Option<Resolvable>>(err);
                    } else {
                        resultingResolvable = resolvable;
                    }

                    break;
                case ModuleMatch.None or ModuleMatch.PreferTheirs or ModuleMatch.Looser:
                    goto default;
                default:
                    break;
            };

            if (resultingResolvable is null) {
                return FinFail<Option<Resolvable>>(Error.New($"Failed to resolve {moduleToResolve.Name}."));
            }

            // Propogate the merge if the module isn't the same.
            if (!ReferenceEquals(foundResolvable, resultingResolvable)) {
                Logger.Debug($"Propogating merge of {foundResolvable.ModuleSpec} with {moduleToResolve}, resulting in {resultingResolvable.ModuleSpec}.");

                this.Graph.TryGetInEdges(foundResolvable, out var inEdges);
                this.Graph.TryGetOutEdges(foundResolvable, out var outEdges);

                inEdges.ToList().ForEach(edge => this.Graph.AddVerticesAndEdge(new Edge<Resolvable>(edge.Source, resultingResolvable)));
                outEdges.ToList().ForEach(edge => this.Graph.AddVerticesAndEdge(new Edge<Resolvable>(resultingResolvable, edge.Target)));

                lock (this.Resolvables) {
                    if (this.Resolvables.TryGetValue(foundResolvable.ModuleSpec, out var resolvableInfo)) {
                        this.Resolvables[resultingResolvable.ModuleSpec] = resolvableInfo;
                    }
                }
            }
        } else {
            var newResolvable = await Resolvable.TryCreate(parentResolvable.AsOption(), moduleToResolve);
            if (newResolvable.IsErr(out var err, out resultingResolvable)) return FinFail<Option<Resolvable>>(err);
        }

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
            this.Graph.AddVertex(resultingResolvable);
        }

        if (!this.Resolvables.TryGetValue(resultingResolvable.ModuleSpec, out var _)) {
            lock (this.Resolvables) {
                this.Resolvables[resultingResolvable.ModuleSpec] = new(None, None, None);
            }
        }

        return FinSucc(Some(resultingResolvable));
    }
}
