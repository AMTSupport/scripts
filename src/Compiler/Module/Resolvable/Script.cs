// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using System.Management.Automation.Language;
using Compiler.Requirements;
using Compiler.Text;
using LanguageExt;

namespace Compiler.Module.Resolvable;

public partial class ResolvableScript : ResolvableLocalModule {
    private readonly ResolvableParent ResolvableParent;

    public ResolvableScript([NotNull] PathedModuleSpec moduleSpec, [NotNull] ResolvableParent superParent) : base(moduleSpec) {
        this.ResolvableParent = superParent;

        #region Requirement Compatability checking
        PSVersionRequirement? highestPSVersion = null;
        PSEditionRequirement? foundPSEdition = null;
        RunAsAdminRequirement? foundRunAsAdmin = null;
        foreach (var resolvable in this.ResolvableParent.Graph.Vertices) {
            var versionRequirement = resolvable.Requirements.GetRequirements<PSVersionRequirement>().FirstOrDefault();
            if (versionRequirement is not null && versionRequirement.Version > highestPSVersion?.Version) highestPSVersion = versionRequirement;

            var editionRequirement = resolvable.Requirements.GetRequirements<PSEditionRequirement>().FirstOrDefault();
            if (editionRequirement is not null && foundPSEdition is not null) {
                if (!editionRequirement.IsCompatibleWith(foundPSEdition)) {
                    throw new IncompatableRequirementsError([editionRequirement, foundPSEdition]);
                }
            }

            foundPSEdition ??= editionRequirement;

            foundRunAsAdmin ??= resolvable.Requirements.GetRequirements<RunAsAdminRequirement>().FirstOrDefault();
        }

        if (highestPSVersion is not null) this.Requirements.AddRequirement(highestPSVersion);
        if (foundPSEdition is not null) this.Requirements.AddRequirement(foundPSEdition);
        if (foundRunAsAdmin is not null) this.Requirements.AddRequirement(foundRunAsAdmin);
        #endregion
    }

    public override Task<Fin<Compiled.Compiled>> IntoCompiled() => CompiledDocument.FromBuilder(this.Editor, 0)
        .AndThenTry(doc => new Compiled.CompiledScript(
            this,
            doc,
            this.ResolvableParent,
            this.ExtractParameterBlock(),
            this.Requirements
        ) as Compiled.Compiled).AsTask();

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
