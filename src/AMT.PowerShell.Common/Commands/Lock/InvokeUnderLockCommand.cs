using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Lock;

/// <summary>Acquires an exclusive file lock, executes a script block, then releases the lock.</summary>
/// <remarks>
/// Derives the script name from the caller, builds the lock path, and waits for the lock
/// before invoking <see cref="ScriptBlock"/>. The lock is always released in a <c>finally</c>
/// block, so it is safe even when the script block throws. Pipeline output from the script
/// block is forwarded to the caller.
/// </remarks>
/// <example>
/// <code>Invoke-UnderLock -ResourceId 'DellDrivers' -ScriptBlock { Install-DellDrivers }</code>
/// Runs driver installation exclusively, preventing concurrent runs for the same resource.
/// </example>
[Cmdlet("Invoke", "UnderLock")]
[OutputType(typeof(object))]
public sealed class InvokeUnderLockCommand : PSCmdlet {
    /// <summary>Resource identifier used to construct the lock file name.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNull]
    public string ResourceId { get; set; } = string.Empty;

    /// <summary>The script block to execute while holding the lock.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNull]
    public ScriptBlock ScriptBlock { get; set; } = null!;

    /// <summary>Optional arguments splatted to the script block when it is invoked.</summary>
    [Parameter(Position = 2)]
    public object[]? ArgumentList { get; set; }

    protected override void ProcessRecord() {
        var resolvedScriptName = LockOperations.ResolveCallerScriptName(
            scriptNameFromParameter: null,
            this.MyInvocation.ScriptName,
            this.MyInvocation.MyCommand?.Name);

        var lockPath = LockOperations.BuildLockPath(resolvedScriptName, this.ResourceId);
        IDisposable? handle = null;

        try {
            handle = LockOperations.WaitForLock(lockPath, this.ResourceId);

            var results = this.ArgumentList is { Length: > 0 }
                ? this.ScriptBlock.Invoke(this.ArgumentList)
                : this.ScriptBlock.Invoke();

            this.WriteObject(results, enumerateCollection: true);
        } finally {
            LockOperations.ReleaseLock(handle, lockPath);
        }
    }
}
