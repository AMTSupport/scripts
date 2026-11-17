using System.IO;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Lock;

/// <summary>Waits for and acquires an exclusive write lock on the specified lock file path.</summary>
/// <remarks>
/// Polls until the lock is available, up to a 600-second timeout.
/// Writes process metadata (PID, optional owner, timestamp) into the lock file.
/// Returns the open <see cref="FileStream"/> handle; pass it to <c>Release-LockFile</c> when done.
/// </remarks>
/// <example>
/// <code>$handle = Wait-LockFile -LockPath $lockPath -LockOwner 'DellDrivers'</code>
/// Acquires the lock and returns the file handle.
/// </example>
[Cmdlet("Wait", "LockFile")]
[OutputType(typeof(FileStream))]
public sealed class WaitLockFileCommand : Cmdlet {
    /// <summary>Full path to the lock file to acquire.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string LockPath { get; set; } = string.Empty;

    /// <summary>Optional owner name written into the lock file metadata for diagnostics.</summary>
    [Parameter(Position = 1)]
    public string? LockOwner { get; set; }

    protected override void ProcessRecord() {
        var handle = LockOperations.WaitForLock(this.LockPath, this.LockOwner);
        this.WriteObject(handle);
    }
}
