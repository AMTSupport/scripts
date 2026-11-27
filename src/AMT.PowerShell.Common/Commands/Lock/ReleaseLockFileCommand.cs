using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Lock;

/// <summary>Releases a lock file handle and removes the lock file from disk.</summary>
/// <remarks>
/// Safely closes the <see cref="LockHandle"/> and deletes the file at <see cref="LockPath"/>.
/// Both parameters are optional; null values are handled gracefully.
/// Prefer <c>Invoke-UnderLock</c> for automatic acquisition and release.
/// </remarks>
/// <example>
/// <code>Release-LockFile -LockHandle $handle -LockPath $lockPath</code>
/// Closes the handle and deletes the lock file.
/// </example>
[Cmdlet("Release", "LockFile")]
public sealed class ReleaseLockFileCommand : Cmdlet {
    /// <summary>The file handle returned by <c>Wait-LockFile</c>; closed if non-null.</summary>
    [Parameter(Position = 0)]
    public IDisposable? LockHandle { get; set; }

    /// <summary>Full path to the lock file to delete; skipped if null or already absent.</summary>
    [Parameter(Position = 1)]
    public string? LockPath { get; set; }

    protected override void ProcessRecord() {
        LockOperations.ReleaseLock(this.LockHandle, this.LockPath);
    }
}
