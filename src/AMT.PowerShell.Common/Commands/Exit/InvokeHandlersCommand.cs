// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Exit;

/// <summary>Runs all registered exit handlers for the current runspace.</summary>
/// <remarks>
/// Iterates every handler registered via <c>Register-ExitHandler</c>.
/// Handlers marked <c>OnlyFailure</c> are skipped unless <see cref="IsFailure"/> is set.
/// Debug and warning messages produced by handlers are forwarded to the calling stream.
/// </remarks>
/// <example>
/// <code>Invoke-Handlers -IsFailure</code>
/// Runs all exit handlers, including those registered with <c>-OnlyFailure</c>.
/// </example>
[Cmdlet("Invoke", "Handlers")]
public sealed class InvokeHandlersCommand : PSCmdlet {
    /// <summary>Indicate that the current exit is a failure, enabling handlers registered with <c>-OnlyFailure</c>.</summary>
    [Parameter]
    public SwitchParameter IsFailure { get; set; }

    protected override void ProcessRecord() =>
        ExitHandlerRunner.Invoke(ExitStore.RequireRunspace(), this.IsFailure.IsPresent, this.WriteDebug, this.WriteWarning);
}
