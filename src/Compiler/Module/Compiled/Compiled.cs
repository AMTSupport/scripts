// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using System.Diagnostics.Contracts;
using System.Security.Cryptography;
using Compiler.Requirements;

namespace Compiler.Module.Compiled;

public abstract class Compiled {
    internal List<Compiled> Parents = [];

    public readonly ModuleSpec ModuleSpec;

    public RequirementGroup Requirements;

    /// <summary>
    /// Gets combined the hash of the content and requirements of the module.
    /// </summary>
    public string ComputedHash;

    /// <summary>
    /// The version of the module, not necessarily the same as the version of the module spec.
    /// </summary>
    public abstract Version Version { get; }

    /// <summary>
    /// Determines how the content string of this module should be interpreted.
    /// </summary>
    public abstract ContentType Type { get; }

    [Pure]
    protected Compiled(ModuleSpec moduleSpec, RequirementGroup requirements, byte[] hashableBytes) {
        this.ModuleSpec = moduleSpec;
        this.Requirements = requirements;

        var byteList = new List<byte>((byte[])hashableBytes.Clone());
        AddRequirementHashBytes(byteList, requirements);
        this.ComputedHash = Convert.ToHexString(SHA256.HashData(byteList.ToArray()));
    }


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

    protected Compiled GetRootParent() {
        if (this.Parents.Count == 0) return this;

        // All parents should point to the same root parent eventually.
        var parent = this.Parents[0];
        while (parent.Parents.Count > 0) {
            parent = parent.Parents[0];
        }

        return parent;
    }

    /// <summary>
    /// Finds all modules which are dependencies of this modules absolute parent.
    /// </summary>
    /// <returns>
    /// An array of compiled modules.
    /// </returns>
    [Pure]
    [return: NotNull]
    protected Compiled[] GetSiblings() {
        var rootParent = this.GetRootParent();
        if (rootParent is not CompiledScript script) return [];

        return script.Graph.Vertices.Where(compiled => compiled != this).ToArray();
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
    protected Compiled? FindSibling([NotNull] ModuleSpec moduleSpec) {
        if (ReferenceEquals(moduleSpec, this.ModuleSpec)) return this;

        var siblings = this.GetSiblings();
        if (siblings.Length == 0) return null;

        return siblings.FirstOrDefault(compiled => compiled.ModuleSpec == moduleSpec);
    }

    public static void AddRequirementHashBytes(
        [NotNull] List<byte> hashableBytes,
        [NotNull] RequirementGroup requirementGroup
    ) {
        var requirements = requirementGroup.GetRequirements();
        requirements.ToList().ForEach(requirement => hashableBytes.AddRange(requirement.Hash));
    }
}

public enum ContentType {
    UTF8String,

    Zip
}
