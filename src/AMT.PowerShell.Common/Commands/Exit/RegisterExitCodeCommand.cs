// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Exit;

/// <summary>Registers a human-readable description for a new exit code and returns the assigned code.</summary>
/// <remarks>
/// Each call allocates the next sequential exit code for the current runspace and stores
/// the supplied description. The description is later retrieved by <c>Invoke-FailedExit</c>
/// to display a meaningful message. Exit codes are runspace-scoped and not shared across sessions.
/// </remarks>
/// <example>
/// <code>$exitCode = Register-ExitCode -Description 'Network connection failed'</code>
/// Registers the description and assigns an integer exit code, returned to <c>$exitCode</c>.
/// </example>
[Cmdlet("Register", "ExitCode")]
[OutputType(typeof(int))]
public sealed class RegisterExitCodeCommand : PSCmdlet {
    /// <summary>Human-readable description shown when this exit code is used with <c>Invoke-FailedExit</c>.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string Description { get; set; } = string.Empty;

    protected override void ProcessRecord() =>
        this.WriteObject(ExitStore.RegisterExitCode(ExitStore.RequireRunspace(), this.Description.Trim()));
}
