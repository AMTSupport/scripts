using System.Diagnostics.Contracts;
using System.Management.Automation.Language;
using Compiler.Requirements;

namespace Compiler.Module.Resolvable;

public partial class ResolvableScript : ResolvableLocalModule
{
    private readonly ResolvableParent ResolvableParent;

    public ResolvableScript(PathedModuleSpec moduleSpec) : base(moduleSpec)
    {
        ResolvableParent = new ResolvableParent(this);
        ResolvableParent.Resolve();

        #region Requirement Compatability checking
        PSVersionRequirement? highestPSVersion = null;
        PSEditionRequirement? foundPSEdition = null;
        RunAsAdminRequirement? foundRunAsAdmin = null;
        foreach (var resolvable in ResolvableParent.Graph.Vertices)
        {
            var versionRequirement = resolvable.Requirements.GetRequirements<PSVersionRequirement>().FirstOrDefault();
            if (versionRequirement != null && versionRequirement.Version > highestPSVersion?.Version) highestPSVersion = versionRequirement;

            var editionRequirement = resolvable.Requirements.GetRequirements<PSEditionRequirement>().FirstOrDefault();
            if (editionRequirement != null && foundPSEdition != null && editionRequirement.Edition != foundPSEdition.Edition) throw new Exception("Multiple PSEditions found in resolved modules.");
            foundPSEdition ??= editionRequirement;

            foundRunAsAdmin ??= resolvable.Requirements.GetRequirements<RunAsAdminRequirement>().FirstOrDefault();
        }

        if (highestPSVersion != null) Requirements.AddRequirement(highestPSVersion);
        if (foundPSEdition != null) Requirements.AddRequirement(foundPSEdition);
        if (foundRunAsAdmin != null) Requirements.AddRequirement(foundRunAsAdmin);
        #endregion
    }

    public override Compiled.Compiled IntoCompiled()
    {
        lock (Requirements)
        {
            return new Compiled.CompiledScript(
                ModuleSpec,
                Editor,
                ResolvableParent,
                ExtractParameterBlock(),
                Requirements
            );
        }
    }

    /// <summary>
    /// Looks for the parameter block of the script,
    /// </summary>
    /// <returns>
    /// The parameter block of the script, if it exists.
    /// </returns>
    public ParamBlockAst? ExtractParameterBlock()
    {
        var scriptParamBlockAst = _ast.ParamBlock;
        if (scriptParamBlockAst == null) return null;

        return scriptParamBlockAst;
    }
}
