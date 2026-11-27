using System.Management.Automation;
using AMT.PowerShell.Common.Module;

namespace AMT.PowerShell.Common.Commands;

/// <summary>Returns the well-known <see cref="RebootFlag"/> that tracks whether a reboot is pending.</summary>
/// <remarks>
/// The reboot flag is a specialised flag with a fixed context. It is set when a component
/// requests a system reboot and cleared after the reboot completes.
/// </remarks>
/// <example>
/// <code>$reboot = Get-RebootFlag; if ($reboot.IsSet) { Restart-Computer }</code>
/// Checks whether a reboot is pending and restarts the computer if so.
/// </example>
[Cmdlet(VerbsCommon.Get, "RebootFlag")]
[OutputType(typeof(RebootFlag))]
public sealed class GetRebootFlagCommand : Cmdlet {
    protected override void ProcessRecord() {
        this.WriteObject(new RebootFlag());
    }
}
