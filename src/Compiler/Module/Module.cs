// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using Compiler.Requirements;

namespace Compiler.Module;

#pragma warning disable CA1716
public abstract partial class Module(ModuleSpec moduleSpec) {
#pragma warning restore CA1716
    public virtual ModuleSpec ModuleSpec { get; } = moduleSpec;

    public RequirementGroup Requirements { get; } = new();

    public abstract ModuleMatch GetModuleMatchFor(ModuleSpec requirement);

    public override int GetHashCode() => this.ModuleSpec.GetHashCode();
}

public enum ModuleMatch : short {
    /// <summary>
    /// This module has incompatible restrictions.
    /// </summary>
    Incompatible = -2,

    /// <summary>
    /// This module does not match the requirements.
    /// </summary>
    None = -1,

    /// <summary>
    /// This module matches the requirements and doesn't have any additional restrictions.
    /// </summary>
    Same = 0,

    /// <summary>
    /// This module matches the requirements, but our module should be used instead.
    /// </summary>
    PreferOurs = 1,

    /// <summary>
    /// This module fulfills the requirements, but the other module should be used instead.
    /// </summary>
    PreferTheirs = 2,

    /// <summary>
    /// This module fulfills the requirements, but has a looser scope.
    /// </summary>
    Looser = 3,

    /// <summary>
    /// This module is both stricter and looser than the requirements, and can be merged.
    /// </summary>
    MergeRequired = 4,

    /// <summary>
    /// This module fulfills the requirements, but has a stricter scope.
    /// </summary>
    Stricter = 5,
}
