// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Exit;

/// <summary>Registers a script block to run when the script exits.</summary>
/// <remarks>
/// Handlers are stored per-runspace and executed in registration order by
/// <c>Invoke-Handlers</c> and <c>Invoke-FailedExit</c>.
/// Re-registering a handler with the same name overwrites the previous entry with a warning.
/// Use <see cref="OnlyFailure"/> to restrict a handler to failure exits only.
/// </remarks>
/// <example>
/// <code>Register-ExitHandler -Name 'Cleanup' -ExitHandler { Remove-Item $tempDir -Recurse }</code>
/// Registers a cleanup handler that runs on every exit.
/// </example>
[Cmdlet("Register", "ExitHandler")]
public sealed class RegisterExitHandlerCommand : PSCmdlet {
    /// <summary>Unique name for this handler; re-using an existing name overwrites the prior registration.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string Name { get; set; } = string.Empty;

    /// <summary>The script block to execute when the script exits.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNull]
    public ScriptBlock ExitHandler { get; set; } = null!;

    /// <summary>Restrict this handler to failure exits; skip it when exiting successfully.</summary>
    [Parameter]
    public SwitchParameter OnlyFailure { get; set; }

    protected override void ProcessRecord() {
        var runspace = ExitStore.RequireRunspace();
        var trimmedName = this.Name.Trim();
        this.WriteDebug($"Registering exit handler '{trimmedName}'");

        if (ExitStore.Contains(runspace, trimmedName)) {
            this.WriteWarning($"Exit handler '{trimmedName}' already registered, overwriting...");
        }

        ExitStore.RegisterHandler(runspace, trimmedName, this.ExitHandler, this.OnlyFailure.IsPresent);
    }
}
