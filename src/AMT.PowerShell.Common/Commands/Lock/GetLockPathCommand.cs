using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Lock;

/// <summary>Returns the full path to the lock file for the given resource and script.</summary>
/// <remarks>
/// Builds a path of the form <c>$TempPath\AMT_{ScriptName}_{ResourceId}.lock</c>.
/// When <see cref="ScriptName"/> is omitted, the name is derived from the caller's script file
/// or command name via <c>MyInvocation</c>.
/// </remarks>
/// <example>
/// <code>$lockPath = Get-LockPath -ResourceId 'DellDrivers'</code>
/// Returns the lock file path for the <c>DellDrivers</c> resource in the current script.
/// </example>
[Cmdlet(VerbsCommon.Get, "LockPath")]
[OutputType(typeof(string))]
public sealed class GetLockPathCommand : PSCmdlet {
    /// <summary>Resource identifier included in the lock file name (e.g. a manufacturer or component name).</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string ResourceId { get; set; } = string.Empty;

    /// <summary>Caller script name used in the lock file name; derived from the call stack when omitted.</summary>
    [Parameter(Position = 1)]
    public string? ScriptName { get; set; }

    protected override void ProcessRecord() {
        var resolvedScriptName = LockOperations.ResolveCallerScriptName(
            this.ScriptName,
            this.MyInvocation.ScriptName,
            this.MyInvocation.MyCommand?.Name);

        var lockPath = LockOperations.BuildLockPath(resolvedScriptName, this.ResourceId);
        this.WriteObject(lockPath);
    }
}
