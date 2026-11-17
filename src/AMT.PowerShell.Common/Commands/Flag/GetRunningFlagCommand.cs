using System.Management.Automation;
using AMT.PowerShell.Common.Module;

namespace AMT.PowerShell.Common.Commands;

/// <summary>Returns the well-known <see cref="RunningFlag"/> that tracks whether the script is currently executing.</summary>
/// <remarks>
/// The running flag is a specialised flag with a fixed context. Set it at script startup and
/// clear it on exit to allow other processes to detect whether this script is active.
/// </remarks>
/// <example>
/// <code>$running = Get-RunningFlag; $running.Set()</code>
/// Retrieves the running flag and marks the script as active.
/// </example>
[Cmdlet(VerbsCommon.Get, "RunningFlag")]
[OutputType(typeof(RunningFlag))]
public sealed class GetRunningFlagCommand : Cmdlet {
    protected override void ProcessRecord() {
        this.WriteObject(new RunningFlag());
    }
}
