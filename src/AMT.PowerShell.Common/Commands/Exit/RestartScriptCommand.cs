// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Exit;

/// <summary>Runs exit handlers and signals the host to restart the current script.</summary>
/// <remarks>
/// Executes all registered exit handlers (non-failure mode), writes an informational restart
/// message, then throws a terminating error with identifier <c>RestartScript</c>.
/// The calling harness is responsible for catching this error and re-launching the script.
/// </remarks>
/// <example>
/// <code>Restart-Script</code>
/// Runs all non-failure exit handlers then signals a restart.
/// </example>
[Cmdlet("Restart", "Script")]
public sealed class RestartScriptCommand : PSCmdlet {
    protected override void ProcessRecord() {
        ExitHandlerRunner.Invoke(ExitStore.RequireRunspace(), false, this.WriteDebug, this.WriteWarning);

        this.WriteInformation("Restarting script...", Array.Empty<string>());

        this.ThrowTerminatingError(new ErrorRecord(
            new Exception("Restart Script"),
            "RestartScript",
            ErrorCategory.NotSpecified,
            null));
    }
}
