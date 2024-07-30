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
    /// If there is none it returns null and makes no changes.
    ///
    /// If there is a param block it removes it from the script and returns an Ast representing the param block.
    /// </summary>
    public ParamBlockAst? ExtractParameterBlock()
    {
        var scriptParamBlockAst = _ast.ParamBlock;

        if (scriptParamBlockAst == null)
        {
            return null;
        }

        Editor.AddExactEdit(
            scriptParamBlockAst.Extent.StartLineNumber - 1,
            scriptParamBlockAst.Extent.StartColumnNumber - 1,
            scriptParamBlockAst.Extent.EndLineNumber - 1,
            scriptParamBlockAst.Extent.EndColumnNumber - 1,
            lines => []
        );

        scriptParamBlockAst.Attributes.ToList().ForEach(attribute =>
        {
            Editor.AddExactEdit(
                attribute.Extent.StartLineNumber - 1,
                attribute.Extent.StartColumnNumber - 1,
                attribute.Extent.EndLineNumber - 1,
                attribute.Extent.EndColumnNumber - 1,
                lines => []
            );
        });

        return scriptParamBlockAst;
    }
}
