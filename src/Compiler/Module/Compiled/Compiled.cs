using System.Diagnostics.Contracts;
using System.Security.Cryptography;
using Compiler.Requirements;

namespace Compiler.Module.Compiled;

public abstract class Compiled
{
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
    protected Compiled(ModuleSpec moduleSpec, RequirementGroup requirements, byte[] hashableBytes)
    {
        ModuleSpec = moduleSpec;
        Requirements = requirements;

        var byteList = new List<byte>(hashableBytes);
        AddRequirementHashBytes(byteList, requirements);
        ComputedHash = Convert.ToHexString(SHA1.HashData(byteList.ToArray()));
    }

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
        Name = '{{ModuleSpec.Name}}';
        Version = '{{Version}}';
        Hash = '{{ComputedHash}}';
        Type = '{{Type}}';
        Content = {{StringifyContent()}}
    }
    """;

    public static void AddRequirementHashBytes(List<byte> hashableBytes, RequirementGroup requirementGroup)
    {
        var requirements = requirementGroup.GetRequirements();
        requirements.ToList().ForEach(requirement => hashableBytes.AddRange(requirement.Hash));
    }

    protected Compiled GetRootParent()
    {
        if (Parents.Count == 0) return this;

        // All parents should point to the same root parent eventually.
        var parent = Parents[0];
        while (parent.Parents.Count > 0)
        {
            parent = parent.Parents[0];
        }

        return parent;
    }

    protected Compiled[] GetSiblings()
    {
        var rootParent = GetRootParent();
        if (rootParent is not CompiledScript script) return [];

        return script.Graph.Vertices.Where(compiled => compiled != this).ToArray();
    }

    protected Compiled? FindSibling(ModuleSpec moduleSpec)
    {
        if (ReferenceEquals(moduleSpec, ModuleSpec)) return this;

        var siblings = GetSiblings();
        if (siblings.Length == 0) return null;

        return siblings.FirstOrDefault(compiled => compiled.ModuleSpec == moduleSpec);
    }
}

public enum ContentType
{
    UTF8String,

    ZipHex
}
