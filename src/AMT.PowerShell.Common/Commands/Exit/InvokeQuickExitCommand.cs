// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Exit;

/// <summary>Runs exit handlers and terminates the pipeline with a success exit code.</summary>
/// <remarks>
/// Executes all registered exit handlers (non-failure mode) and then throws a terminating error
/// with the identifier <c>QuickExit</c>. Use this when a script should stop cleanly without
/// indicating a failure condition.
/// </remarks>
/// <example>
/// <code>Invoke-QuickExit</code>
/// Runs all non-failure exit handlers then terminates the pipeline immediately.
/// </example>
[Cmdlet("Invoke", "QuickExit")]
public sealed class InvokeQuickExitCommand : PSCmdlet {
    protected override void ProcessRecord() {
        ExitHandlerRunner.Invoke(ExitStore.RequireRunspace(), false, this.WriteDebug, this.WriteWarning);

        this.ThrowTerminatingError(new ErrorRecord(
            new Exception("Quick Exit"),
            "QuickExit",
            ErrorCategory.NotSpecified,
            null));
    }
}
