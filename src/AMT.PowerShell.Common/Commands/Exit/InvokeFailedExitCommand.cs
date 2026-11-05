// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Globalization;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Exit;

/// <summary>Runs exit handlers and terminates the pipeline with a non-zero exit code.</summary>
/// <remarks>
/// Looks up the registered description for <see cref="ExitCode"/> and writes it as an error display
/// message. If an <see cref="ErrorRecord"/> is supplied the deepest exception message is also shown.
/// All registered exit handlers are executed before the terminating error is thrown.
/// Pass <see cref="DontExit"/> to suppress the terminating error (useful in tests).
/// </remarks>
/// <example>
/// <code>Invoke-FailedExit -ExitCode 1 -ErrorRecord $err</code>
/// Displays the description registered for exit code 1, runs all exit handlers,
/// then throws a terminating error carrying exit code 1.
/// </example>
[Cmdlet("Invoke", "FailedExit")]
public sealed class InvokeFailedExitCommand : PSCmdlet {
    /// <summary>The numeric exit code to return to the caller.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public int ExitCode { get; set; }

    /// <summary>The error record that caused the exit; its deepest exception message is displayed.</summary>
    [Parameter]
    public ErrorRecord? ErrorRecord { get; set; }

    /// <summary>Suppress the terminating error after running handlers; the cmdlet returns normally instead.</summary>
    [Parameter]
    public SwitchParameter DontExit { get; set; }

    /// <summary>Format arguments applied to the registered exit-code description string via <c>string.Format</c>.</summary>
    [Parameter]
    public string[]? FormatArgs { get; set; }

    protected override void ProcessRecord() {
        var runspace = ExitStore.RequireRunspace();
        var description = ExitStore.GetDescription(runspace, this.ExitCode);

        if (!string.IsNullOrEmpty(description)) {
            if (this.FormatArgs is { Length: > 0 }) {
                description = string.Format(CultureInfo.InvariantCulture, description, this.FormatArgs);
            }

            this.WriteErrorDisplay(description!);
        } else if (this.ExitCode != 0 && this.ExitCode != 9999) {
            this.WriteErrorDisplay($"Exit code {this.ExitCode}");
        }

        Exception? deepestException = null;
        if (this.ErrorRecord is not null) {
            deepestException = this.ErrorRecord.Exception;
            var deepestMessage = deepestException?.Message;

            while (deepestException?.InnerException is not null) {
                var inner = deepestException.InnerException;
                deepestException = inner;
                if (!string.IsNullOrEmpty(inner.Message)) {
                    deepestMessage = inner.Message;
                }

                // Legacy descends only while inner exceptions carry an
                // ErrorRecord, which is PowerShell-only state. Descend one
                // level and stop to avoid unbounded traversal of plain chains.
                break;
            }

            if (!string.IsNullOrEmpty(deepestMessage)) {
                this.WriteErrorDisplay(deepestMessage!);
            }
        }

        ExitHandlerRunner.Invoke(runspace, this.ExitCode != 0, this.WriteDebug, this.WriteWarning);

        if (this.DontExit) {
            return;
        }

        deepestException ??= !string.IsNullOrEmpty(description)
            ? new Exception(description)
            : new Exception("Failed Exit");

        var category = this.ErrorRecord?.CategoryInfo.Category ?? ErrorCategory.NotSpecified;

        this.ThrowTerminatingError(new ErrorRecord(
            deepestException,
            "FailedExit",
            category,
            this.ExitCode));
    }

    private void WriteErrorDisplay(string message) =>
        this.WriteInformation("❌ " + message, new[] { "AMT.ErrorDisplay" });
}
