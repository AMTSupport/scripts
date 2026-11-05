// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Scope;

/// <summary>Returns the formatted display name for the current top-of-stack scope.</summary>
/// <remarks>
/// Delegates to <see cref="ScopeStack.FormatName"/> for the current runspace.
/// The formatted name reflects entry or exit style depending on -IsExit.
/// </remarks>
/// <example>
/// <code>Format-ScopeName</code>
/// Returns the entry-style name of the innermost scope.
/// </example>
/// <example>
/// <code>Format-ScopeName -IsExit</code>
/// Returns the exit-style name of the innermost scope.
/// </example>
[Cmdlet("Format", "ScopeName")]
[OutputType(typeof(string))]
public sealed class FormatScopeNameCommand : PSCmdlet {
    /// <summary>When set, formats the name as it appears on scope exit rather than entry.</summary>
    [Parameter]
    public SwitchParameter IsExit { get; set; }

    protected override void ProcessRecord() =>
        this.WriteObject(ScopeStack.FormatName(ScopeStack.RequireRunspace(), this.IsExit));
}
