using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Windows;

/// <summary>Forces a W32TM time resynchronisation if the last sync exceeds the threshold age.</summary>
/// <remarks>
/// Checks the age of the last successful sync via Get-LastSyncTime.
/// Returns <see langword="true"/> when a resync was triggered and succeeded,
/// <see langword="false"/> when the existing sync time is within the threshold.
/// Windows-only; requires the w32tm service to be running.
/// </remarks>
/// <example>
/// <code>Sync-Time</code>
/// Resyncs the clock if the last sync was more than 7 days ago.
/// </example>
/// <example>
/// <code>Sync-Time -Threshold ([TimeSpan]::FromHours(1))</code>
/// Resyncs the clock if the last sync was more than 1 hour ago.
/// </example>
[Cmdlet("Sync", "Time")]
[OutputType(typeof(bool))]
public sealed class SyncTimeCommand : PSCmdlet {
    /// <summary>Maximum allowed age of the last sync before a resync is triggered; defaults to 7 days.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public TimeSpan Threshold { get; set; } = TimeSpan.FromDays(7);

    protected override void ProcessRecord() {
        var lastSyncTime = GetLastSyncTimeCommand.GetLastSyncTime();
        var currentTime = DateTime.Now;

        if ((currentTime - lastSyncTime) <= this.Threshold) {
            this.WriteObject(false);
            return;
        }

        this.WriteObject(GetLastSyncTimeCommand.TryResyncTime());
    }
}
