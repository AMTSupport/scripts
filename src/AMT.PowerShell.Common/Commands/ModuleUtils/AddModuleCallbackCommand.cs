// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.ModuleUtils;

/// <summary>Registers a ScriptBlock to be invoked when a module is removed from the session.</summary>
/// <remarks>
/// The target module is resolved from the PowerShell call stack when <c>-Module</c> is omitted,
/// so this cmdlet must be called from within module-level code.
/// Throws a terminating error if no module context can be resolved.
/// </remarks>
/// <example>
/// <code>Add-ModuleCallback -ScriptBlock { Write-Host "Module unloaded" }</code>
/// Registers a cleanup handler for the calling module.
/// </example>
[Cmdlet(VerbsCommon.Add, "ModuleCallback")]
public sealed class AddModuleCallbackCommand : PSCmdlet {
    /// <summary>The ScriptBlock to invoke when the target module is removed.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNull]
    public ScriptBlock ScriptBlock { get; set; } = null!;

    /// <summary>The module to register the callback for; resolved from the call stack when omitted.</summary>
    [Parameter(Position = 1)]
    public PSModuleInfo? Module { get; set; }

    protected override void EndProcessing() {
        var module = ResolveModule();
        if (module is null) {
            ThrowTerminatingError(new ErrorRecord(
                new InvalidOperationException("This function must be called from within a module."),
                "ModuleCallbackRequiresModule",
                ErrorCategory.InvalidOperation,
                null));
            return;
        }

        ModuleCallback.Add(module, this.ScriptBlock, this.SessionState);
    }

    private PSModuleInfo? ResolveModule() {
        if (this.Module is not null) {
            return this.Module;
        }

        return CallerModuleResolver.Resolve(this);
    }
}
