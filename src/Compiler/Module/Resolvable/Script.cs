// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation.Language;
using Compiler.Requirements;

namespace Compiler.Module.Resolvable;

public partial class ResolvableScript : ResolvableLocalModule {
    private readonly ResolvableParent ResolvableParent;

    public ResolvableScript(PathedModuleSpec moduleSpec, ResolvableParent superParent) : base(moduleSpec) {
        this.ResolvableParent = superParent;

        #region Requirement Compatability checking
        PSVersionRequirement? highestPSVersion = null;
        PSEditionRequirement? foundPSEdition = null;
        RunAsAdminRequirement? foundRunAsAdmin = null;
        foreach (var resolvable in this.ResolvableParent.Graph.Vertices) {
            var versionRequirement = resolvable.Requirements.GetRequirements<PSVersionRequirement>().FirstOrDefault();
            if (versionRequirement != null && versionRequirement.Version > highestPSVersion?.Version) highestPSVersion = versionRequirement;

            var editionRequirement = resolvable.Requirements.GetRequirements<PSEditionRequirement>().FirstOrDefault();
            if (editionRequirement != null
                && foundPSEdition != null
                && editionRequirement.Edition != foundPSEdition.Edition
            ) throw new Exception("Multiple PSEditions found in resolved modules.");

            foundPSEdition ??= editionRequirement;

            foundRunAsAdmin ??= resolvable.Requirements.GetRequirements<RunAsAdminRequirement>().FirstOrDefault();
        }

        if (highestPSVersion != null) _ = this.Requirements.AddRequirement(highestPSVersion);
        if (foundPSEdition != null) _ = this.Requirements.AddRequirement(foundPSEdition);
        if (foundRunAsAdmin != null) _ = this.Requirements.AddRequirement(foundRunAsAdmin);
        #endregion
    }

    public override Compiled.Compiled IntoCompiled() {
        lock (this.Requirements) {
            return new Compiled.CompiledScript(
                this.ModuleSpec,
                this.Editor,
                this.ResolvableParent,
                this.ExtractParameterBlock(),
                this.Requirements
            );
        }
    }

    /// <summary>
    /// Looks for the parameter block of the script,
    /// </summary>
    /// <returns>
    /// The parameter block of the script, if it exists.
    /// </returns>
    public ParamBlockAst? ExtractParameterBlock() {
        var scriptParamBlockAst = this.Ast.ParamBlock;
        return scriptParamBlockAst ?? null;
    }
}
