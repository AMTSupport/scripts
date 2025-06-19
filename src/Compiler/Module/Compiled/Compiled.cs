// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using System.Diagnostics.Contracts;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text;
using Compiler.Module.Resolvable;
using Compiler.Requirements;
using LanguageExt;
using NLog;

namespace Compiler.Module.Compiled;

[method: Pure]
public abstract class Compiled(ModuleSpec moduleSpec, RequirementGroup requirements) {
    public Compiled(
        ModuleSpec moduleSpec,
        RequirementGroup requirements,
        Lazy<byte[]> contentBytes
    ) : this(moduleSpec, requirements) => this.ContentBytes = contentBytes;

    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public virtual Option<CompiledScript> RootScript { get; set; }

    public virtual List<Compiled> Parents { get; } = [];

    public virtual ModuleSpec ModuleSpec { get; } = moduleSpec;

    public virtual RequirementGroup Requirements { get; } = requirements;

    /// <summary>
    /// This is the resolving parent of this module which can be used to reference other info the module may need.
    ///
    /// This will be null during the initialisation of the object, but will be set after object creation.
    /// </summary>
    [NotNull]
    public required ResolvableParent ResolvableParent { get; set; }

    [NotNull]
    public Lazy<byte[]>? ContentBytes { get; protected set; }

    /// <summary>
    /// Gets combined the hash of the content and requirements of the module.
    /// </summary>
    public string ComputedHash {
        // For some reason these values are not always gotten at their latest after an update, its like its doing some bullshit premature optimization.
        // So we need to tell the compiler to not optimize this method.
        [MethodImpl(MethodImplOptions.NoInlining | MethodImplOptions.NoOptimization)]
        get {
            var byteList = new List<byte>((byte[])this.ContentBytes!.Value.Clone());
            this.AddRequirementHashBytes(byteList, this.Requirements);
            return Convert.ToHexString(SHA256.HashData([.. byteList]));
        }
    }

    /// <summary>
    /// The version of the module, not necessarily the same as the version of the module spec.
    /// </summary>
    public abstract Version Version { get; }

    /// <summary>
    /// Determines how the content string of this module should be interpreted.
    /// </summary>
    public abstract ContentType Type { get; }

    public string GetNameHash() => $"{this.ModuleSpec.Name}-{this.ComputedHash[..6]}";

    public abstract string StringifyContent();

    public abstract IEnumerable<string> GetExportedFunctions();

    /// <summary>
    /// Gets a PowerShell Hashtable that represents this module.
    /// </summary>
    /// <returns>
    /// A Stringified PowerShell Hashtable.
    /// </returns>
    public virtual string GetPowerShellObject() => $$"""
    @{
        Name = '{{this.ModuleSpec.Name}}';
        Version = '{{this.Version}}';
        Hash = '{{this.ComputedHash[..6]}}';
        Type = '{{this.Type}}';
        Content = {{this.StringifyContent()}}
    }
    """;

    /// <summary>
    /// Gets the absolute parent of the module, which should always be the executing script.
    /// </summary>
    /// <returns>
    /// The absolute parent of the module.
    /// </returns>
    /// <remarks
    /// While this method is nullable, it should never return null in practice.
    /// </remarks>
    public virtual CompiledScript? GetRootParent() {
        if (this.RootScript.IsSome) return this.RootScript.Unwrap();
        if (this.Parents.Count == 0) {
            Logger.Warn($"Module {this.ModuleSpec.Name} has no parents and is not a script.");
            return null; // If it was a script it would have overriden this method.
        }

        // All parents should point to the same root parent eventually.
        var parent = this.Parents[0];
        while (parent.Parents.Count > 0) {
            parent = parent.Parents[0];
        }

        return parent as CompiledScript;
    }

    /// <summary>
    /// Finds all modules which are dependencies of this modules absolute parent.
    /// </summary>
    /// <returns>
    /// An array of compiled modules.
    /// </returns>
    [Pure]
    [return: NotNull]
    public Compiled[] GetSiblings() {
        var rootParent = this.GetRootParent();
        if (rootParent is not CompiledScript script) return [];

        return [.. script.Graph.Vertices.Where(compiled => compiled != this)];
    }

    /// <summary>
    /// Finds a sibling of this module, if it exists.
    /// </summary>
    /// <param name="moduleSpec">
    /// The module spec of the sibling to find.
    /// </param>
    /// <returns>
    /// The sibling if it exists, otherwise null.
    /// </returns>
    [Pure]
    public Compiled? FindSibling([NotNull] ModuleSpec moduleSpec) {
        if (ReferenceEquals(moduleSpec, this.ModuleSpec)) return this;

        var siblings = this.GetSiblings();
        if (siblings.Length == 0) return null;

        return siblings.FirstOrDefault(compiled => compiled.ModuleSpec == moduleSpec);
    }

    [Pure]
    public void AddRequirementHashBytes(
        [NotNull] List<byte> hashableBytes,
        [NotNull] RequirementGroup requirementGroup
    ) {
        hashableBytes.AddRange(requirementGroup.GetRequirements()
            .Select(req => req.Hash)
            .Flatten());

        var rootGraph = this.GetRootParent()!.Graph;
        if (!rootGraph.ContainsVertex(this)) {
            // How tf did this happen?
            Logger.Error($"Module {this.ModuleSpec.Name} is not in the graph of its root parent.");
        }

        hashableBytes.AddRange(rootGraph.OutEdges(this).ToList()
            .Select(edge => edge.Target.ComputedHash)
            .Select(Encoding.UTF8.GetBytes)
            .Flatten());
    }

    /// <summary>
    /// Gets all dependencies and their dependencies of this module.
    /// </summary>
    /// <returns>A list of compiled modules.</returns>
    [Pure]
    public List<Compiled> GetDownstreamModules() {
        var rootParent = this.GetRootParent();
        if (rootParent is not CompiledScript script) return [];

        var downstreamModules = new List<Compiled>();
        var graph = script.Graph.Clone();
        while (graph.OutDegree(this) > 0) {
            var edges = graph.OutEdges(this).ToList();
            foreach (var edge in edges) {
                var target = edge.Target;
                if (target is Compiled compiled) {
                    downstreamModules.Add(compiled);
                    graph.RemoveEdge(edge);
                }
            }
        }

        return [.. downstreamModules.Distinct()];
    }

    /// <summary>
    /// Gets a compiled module from a resolvable, if it exists.
    /// This will search the root parent of this module for the compiled module.
    /// </summary>
    /// <param name="resolvable"></param>
    /// <returns></returns>
    [Pure]
    public Option<Compiled> GetCompiledFromResolvable(
        [NotNull] Resolvable.Resolvable resolvable
    ) {
        var rootParent = this.GetRootParent();
        if (rootParent is not CompiledScript script) return Option<Compiled>.None;

        return script.Graph.Vertices.FirstOrDefault(compiled =>
            compiled.ModuleSpec == resolvable.ModuleSpec);
    }

    /// <summary>
    /// Completes the compile process after all modules have been resolved.
    ///
    /// This is called after all modules have been resolved and their dependencies have been resolved.
    /// This stage should not make any changes that will change the module's hash.
    /// </summary>
    public virtual void CompleteCompileAfterResolution() {

    }
}

public enum ContentType {
    UTF8String,

    Zip
}
