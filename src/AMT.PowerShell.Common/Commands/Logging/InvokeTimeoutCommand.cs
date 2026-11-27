// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Diagnostics;
using System.Globalization;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Logging;

/// <summary>Displays a countdown progress bar for a fixed duration, then invokes a callback.</summary>
/// <remarks>
/// The progress bar ticks approximately every 50 ms.
/// If <c>-AllowCancel</c> is set and a key is pressed before the timeout elapses,
/// <c>CancelScript</c> is invoked instead of <c>TimeoutScript</c>.
/// </remarks>
/// <example>
/// <code>
/// Invoke-Timeout -Timeout 10 -Activity "Waiting" -StatusMessage "{0}s remaining" -TimeoutScript { Restart-Computer }
/// </code>
/// Counts down 10 seconds, then restarts the computer.
/// </example>
[Cmdlet(VerbsLifecycle.Invoke, "Timeout")]
public sealed class InvokeTimeoutCommand : PSCmdlet {
    /// <summary>Timeout duration in seconds.</summary>
    [Parameter(Mandatory = true)]
    public int Timeout { get; set; }

    /// <summary>Activity label shown in the progress bar header.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    public string Activity { get; set; } = string.Empty;

    /// <summary>Format string for the progress status; <c>{0}</c> is replaced with the whole seconds remaining.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    public string StatusMessage { get; set; } = string.Empty;

    /// <summary>ScriptBlock invoked when the timeout elapses without cancellation.</summary>
    [Parameter]
    public ScriptBlock? TimeoutScript { get; set; }

    /// <summary>ScriptBlock invoked when the user cancels before the timeout elapses.</summary>
    [Parameter]
    public ScriptBlock? CancelScript { get; set; }

    /// <summary>When set, the user can press any key to cancel the countdown and invoke <c>CancelScript</c>.</summary>
    [Parameter]
    public SwitchParameter AllowCancel { get; set; }

    protected override void ProcessRecord() {
        const int progressId = 0;
        var totalMilliseconds = (double)this.Timeout * 1000.0;
        var stopwatch = Stopwatch.StartNew();
        var cancelled = this.AllowCancel.IsPresent && LoggingRuntime.ConsoleKeyAvailable;

        while (!cancelled) {
            var elapsed = stopwatch.Elapsed.TotalMilliseconds;
            if (elapsed >= totalMilliseconds) {
                break;
            }

            var remaining = totalMilliseconds - elapsed;
            this.WriteProgress(BuildProgress(progressId, this.Activity, this.StatusMessage, remaining, totalMilliseconds));

            LoggingRuntime.Sleep((int)Math.Min(50, Math.Max(1, remaining)));
            cancelled = this.AllowCancel.IsPresent && LoggingRuntime.ConsoleKeyAvailable;
        }

        this.WriteProgress(new ProgressRecord(progressId, this.Activity, "Completed") {
            RecordType = ProgressRecordType.Completed,
        });

        if (cancelled) {
            this.CancelScript?.Invoke();
        } else {
            this.TimeoutScript?.Invoke();
        }
    }

    private static ProgressRecord BuildProgress(int id, string activity, string statusMessage, double remainingMilliseconds, double totalMilliseconds) {
        var percent = totalMilliseconds <= 0
            ? 100
            : (int)((totalMilliseconds - remainingMilliseconds) / totalMilliseconds * 100.0);
        var status = FormatStatus(statusMessage, remainingMilliseconds);

        return new ProgressRecord(id, activity, status) {
            PercentComplete = Math.Max(0, Math.Min(100, percent)),
        };
    }

    private static string FormatStatus(string statusMessage, double remainingMilliseconds) {
        var seconds = (int)Math.Ceiling(remainingMilliseconds / 1000.0);

        try {
            return string.Format(CultureInfo.InvariantCulture, statusMessage, seconds);
        } catch (FormatException) {
            return statusMessage;
        }
    }
}
