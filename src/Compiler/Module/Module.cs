using Compiler.Requirements;

namespace Compiler.Module;

public abstract partial class Module(ModuleSpec moduleSpec)
{
    public virtual ModuleSpec ModuleSpec { get; } = moduleSpec;

    public RequirementGroup Requirements { get; } = new();

    public abstract ModuleMatch GetModuleMatchFor(ModuleSpec requirement);

    public override int GetHashCode() => ModuleSpec.GetHashCode();
}

public enum ModuleMatch
{
    /// <summary>
    /// This module matches the requirements and doesn't have any additional restrictions.
    /// </summary>
    Same,

    /// <summary>
    /// This module is both stricter and looser than the requirements, and can be merged.
    /// </summary>
    MergeRequired,

    /// <summary>
    /// This module fulfills the requirements, but has a stricter scope.
    /// </summary>
    Stricter,

    /// <summary>
    /// This module fulfills the requirements, but has a looser scope.
    /// </summary>
    Looser,

    /// <summary>
    /// This module has incompatible restrictions.
    /// </summary>
    Incompatible,

    /// <summary>
    /// This module does not match the requirements.
    /// </summary>
    None
}
