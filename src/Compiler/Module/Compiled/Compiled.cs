using System.Text;
using Compiler.Requirements;

namespace Compiler.Module.Compiled;

public abstract partial class Compiled(ModuleSpec moduleSpec)
{
    public readonly ModuleSpec ModuleSpec = moduleSpec;

    public required RequirementGroup Requirements;

    /// <summary>
    /// Gets combined the hash of the content and requirements of the module.
    /// </summary>
    public abstract string ComputedHash { get; }

    /// <summary>
    /// Determines how the content string of this module should be interpreted.
    /// </summary>
    public abstract ContentType ContentType { get; }

    /// <summary>
    /// The version of the module, not necessarily the same as the version of the module spec.
    /// </summary>
    public abstract Version Version { get; }

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
        Type = '{{ContentType}}';
        Content = {{StringifyContent()}}
    }
    """;
}

public enum ContentType
{
    UTF8String,
    ZipHex
}
