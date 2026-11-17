using System.Management.Automation;
using AMT.PowerShell.Common.Module;

namespace AMT.PowerShell.Common.Commands;

/// <summary>Returns identifying metadata for the AMT.PowerShell.Common binary module.</summary>
/// <remarks>
/// Emits a single ModuleInfo object containing the module name, assembly version,
/// and a short description.
/// </remarks>
/// <example>
/// <code>Get-AMTModuleInfo</code>
/// Returns the name, version, and description of the loaded AMT.PowerShell.Common module.
/// </example>
[Cmdlet(VerbsCommon.Get, "AMTModuleInfo")]
[OutputType(typeof(ModuleInfo))]
public sealed class GetModuleInfoCommand : Cmdlet {
    protected override void ProcessRecord() {
        WriteObject(new ModuleInfo(
            "AMT.PowerShell.Common",
            typeof(GetModuleInfoCommand).Assembly.GetName().Version?.ToString() ?? "0.0.0",
            "Repo-local PowerShell binary module scaffold."));
    }
}
