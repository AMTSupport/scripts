// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections.ObjectModel;
using System.Diagnostics.CodeAnalysis;
using System.Management.Automation;
using Compiler.Module.Compiled;
using Compiler.Requirements;
using LanguageExt;
using LanguageExt.UnsafeValueAccess;
using NLog;
using QuikGraph;
using QuikGraph.Graphviz;

namespace Compiler.Module.Resolvable;

public abstract partial class Resolvable(ModuleSpec moduleSpec) : Module(moduleSpec) {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public ManualResetEvent RequirementsWaitHandle { get; } = new ManualResetEvent(false);

    public bool RequirementsResolved { get; private set; }

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

    protected virtual void QueueResolve() => ThreadPool.QueueUserWorkItem(async _ => {
        try {
            (await this.ResolveRequirements()).Match(
                exception => {
                    Program.Errors.Add(exception);
                    Program.CancelSource.Cancel(true);
                },
                () => Logger.Debug($"Finished resolving requirements for module {this.ModuleSpec.Name}.")
            );
        } catch (Exception err) {
            Program.Errors.Add(Error.New($"Failed to resolve requirements for module {this.ModuleSpec.Name}.", err));
            Program.CancelSource.Cancel(true);
            return;
        }

        this.RequirementsWaitHandle.Set();
        this.RequirementsResolved = true;
    }, Program.CancelSource.Token);

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
    internal static Fin<Resolvable> TryCreate(
        [NotNull] Option<Resolvable> parentResolvable,
        [NotNull] ModuleSpec moduleSpec,
        Collection<ModuleSpec>? mergeWith = default
    ) {
        if (mergeWith is not null && mergeWith.Count != 0) {
            moduleSpec = moduleSpec.MergeSpecs([.. mergeWith]);
        }

        if (parentResolvable.IsSome(out var parent) && parent is ResolvableLocalModule localParent) {
            var parentPath = Path.GetDirectoryName(localParent.ModuleSpec.FullPath)!;
            try {
                Logger.Debug($"Looking for {moduleSpec.Name} module in {parentPath}.");
                var localModule = new ResolvableLocalModule(parentPath, moduleSpec);
                localModule.QueueResolve();
                return FinSucc(localModule as Resolvable);
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

        try {
            var remote = new ResolvableRemoteModule(moduleSpec);
            remote.QueueResolve();

            return FinSucc(remote as Resolvable);
        } catch (Exception err) {
            return FinFail<Resolvable>(err);
        }
    }

    internal static Fin<ResolvableScript> TryCreateScript([NotNull] PathedModuleSpec moduleSpec, [NotNull] ResolvableParent parent) {
        try {
            var script = new ResolvableScript(moduleSpec, parent);
            script.QueueResolve();
            return FinSucc(script);
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
        [NotNull] Option<ManualResetEvent> WaitHandle
    );

    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

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

        var iterating = new Queue<Resolvable>([resolvable]);
        do {
            var currentResolvable = iterating.Dequeue();
            lock (this.Graph) {
                this.Graph.TryGetOutEdges(currentResolvable, out var outEdges);
                outEdges.ToList().ForEach(edge => {
                    graph.AddVerticesAndEdge(edge);
                    iterating.Enqueue(edge.Target);
                });
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
    public ResolvedMatch? FindResolvable(ModuleSpec moduleSpec) {
        var resolvable = this.Graph.Vertices.FirstOrDefault(resolvable => resolvable.ModuleSpec.CompareTo(moduleSpec) != ModuleMatch.None);
        if (resolvable == null) return null;

        Logger.Debug($"Found resolvable {resolvable.ModuleSpec.Name} for {moduleSpec.Name}.");
        return new(resolvable, resolvable.ModuleSpec.CompareTo(moduleSpec));
    }

    public async Task<Fin<Compiled.Compiled>> WaitForCompiled(ModuleSpec moduleSpec) {
        var resolvableMatch = this.FindResolvable(moduleSpec);
        if (resolvableMatch == null) {
            return FinFail<Compiled.Compiled>(Error.New($"No resolvable found for {moduleSpec}."));
        }

        var (resolvable, match) = resolvableMatch;
        if (match == ModuleMatch.None) {
            return FinFail<Compiled.Compiled>(Error.New($"No matching resolvable found for {moduleSpec}."));
        }

        if (!resolvable.RequirementsResolved) {
            await resolvable.RequirementsWaitHandle.WaitOneAsync(10000, Program.CancelSource.Token);
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
        if (waitHandle.IsSome(out var handle)) {
            Logger.Debug($"Waiting for IntoCompiled to finish for {moduleSpec.Name}.");
            await handle.WaitOneAsync(10000, Program.CancelSource.Token);

            if (this.Resolvables.TryGetValue(moduleSpec, out resolvableInfo)) {
                (compiledOpt, _, _) = resolvableInfo;

                // Safety: We know its going to be some here due waitHandle being some and having triggered.
                if (compiledOpt.Unwrap().IsErr(out var err, out var compiled)) {
                    return FinFail<Compiled.Compiled>(err);
                }

                return FinSucc(compiled);
            }

            return FinFail<Compiled.Compiled>(Error.New($"Failed to find compiled module for {moduleSpec.Name} after waiting for it."));
        } else {
            var newWaitHandle = new ManualResetEvent(false);
            lock (this.Resolvables) {
                this.Resolvables[moduleSpec] = resolvableInfo with {
                    WaitHandle = newWaitHandle
                };
            }

            var newlyCompiledModule = await resolvable.IntoCompiled();
            newlyCompiledModule.IfFail(err => Logger.Error(err.Message));

            lock (this.Resolvables) {
                this.Resolvables[moduleSpec] = resolvableInfo with {
                    Compiled = newlyCompiledModule
                };
            }

            newlyCompiledModule.IfSucc(module => onCompletion.IfSome(
                onCompletion => onCompletion((module as CompiledScript)!) // Safety: We know it's a compiled script
            ));

            newWaitHandle.Set();
            return newlyCompiledModule;
        }
    }

    public async Task StartCompilation() {
        await this.ResolveDepedencyGraph();

        // Get a list of the scripts which are roots and have no scripts depending on them.
        var topLevelScripts = this.Graph.Vertices.Where(resolvable => !this.Graph.TryGetInEdges(resolvable, out var inEdges) || !inEdges.Any());
        topLevelScripts.AsParallel().ForAll(async resolvable => {
            Logger.Trace($"Compiling top level script {resolvable.ModuleSpec.Name}");

            var compiledModule = await this.WaitForCompiled(resolvable.ModuleSpec);
            compiledModule.IfFail(Program.Errors.Add);

            Logger.Debug($"Finished compiling top level script {resolvable.ModuleSpec.Name}");
        });

        Logger.Trace("Finished compiling all top level scripts.");
    }

    /// <summary>
    /// Creates all the links between the modules and their dependencies.
    /// </summary>
    private async Task ResolveDepedencyGraph() {
        var iterating = new Queue<(Resolvable?, ModuleSpec)>(this.Graph.Vertices.Select(resolvable => ((Resolvable?)null, resolvable.ModuleSpec)));
        while (iterating.Count > 0) {
            var (parentResolvable, workingModuleSpec) = iterating.Dequeue();
            Logger.Trace($"Resolving {workingModuleSpec} with parent {parentResolvable?.ModuleSpec}.");

            // If the parent module has already been resolved this will be an orphan.
            if (parentResolvable != null && !this.Graph.ContainsVertex(parentResolvable)) {
                Logger.Debug("Parent module had already been resolved, skipping orphan.");
                continue;
            }

            var resolvableResult = this.LinkFindingPossibleResolved(parentResolvable, workingModuleSpec);

            Option<Resolvable> workingResolvable = None;
            switch (resolvableResult) {
                case var fail when fail.IsFail:
                    Logger.Error($"Failed to link {workingModuleSpec} to {parentResolvable?.ModuleSpec}.");
                    fail.IfFail(Program.Errors.Add);
                    continue;
                case var succ when succ.IsSucc:
                    Logger.Debug($"Linked {workingModuleSpec} to {parentResolvable?.ModuleSpec}.");
                    workingResolvable = succ.Unwrap();
                    break;
                default:
                    break;
            }

            // If it was null or there are out edges it means this module has already been resolved.
            if (workingResolvable.IsNone || (this.Graph.TryGetOutEdges(workingResolvable.ValueUnsafe()!, out var outEdges) && outEdges.Any())) {
                Logger.Debug("Module has already been resolved, skipping.");
                continue;
            }

            var safeWorkingResolvable = workingResolvable.ValueUnsafe()!;
            // TODO Maybe push to the end of the queue or something.
            if (!safeWorkingResolvable.RequirementsResolved) {
                if (iterating.Count == 0) {
                    Logger.Debug("Requirements not resolved, waiting for them to be resolved.");
                    await safeWorkingResolvable.RequirementsWaitHandle.WaitOneAsync(-1, Program.CancelSource.Token);
                } else {
                    Logger.Debug("Requirements not resolved, pushing to the end of the queue.");
                    iterating.Enqueue((parentResolvable, workingModuleSpec));
                    continue;
                }
            }

            lock (safeWorkingResolvable.Requirements) {
                safeWorkingResolvable.Requirements.GetRequirements<ModuleSpec>().ToList().ForEach(requirement => iterating.Enqueue((safeWorkingResolvable, requirement)));
            }
        }

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
    public Fin<Option<Resolvable>> LinkFindingPossibleResolved(
        Resolvable? parentResolvable,
        [NotNull] ModuleSpec moduleToResolve) {
        ArgumentNullException.ThrowIfNull(moduleToResolve);

        var resolveableMatch = this.FindResolvable(moduleToResolve);
        Resolvable? resultingResolvable = null;
        if (resolveableMatch != null) {
            Logger.Debug($"Found existing resolvable for {moduleToResolve.Name}.");

            resolveableMatch.Deconstruct(out var foundResolvable, out var match);
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

                    var fin = Resolvable.TryCreate(
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

            if (resultingResolvable == null) {
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
            var newResolvable = Resolvable.TryCreate(parentResolvable.AsOption(), moduleToResolve);
            if (newResolvable.IsErr(out var err, out _)) return FinFail<Option<Resolvable>>(err);
            resultingResolvable = newResolvable.Unwrap();
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
