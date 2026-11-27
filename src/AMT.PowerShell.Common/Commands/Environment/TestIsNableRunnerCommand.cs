// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.EnvironmentCmdlets;

/// <summary>Return <see langword="true"/> when the current session is hosted inside the N-able fmplugin.exe process.</summary>
/// <remarks>
/// Inspects the console window-title leaf and compares it case-insensitively to <c>fmplugin.exe</c>.
/// Use this to suppress UI-heavy output paths that do not render correctly inside the N-able runner.
/// </remarks>
/// <example>
/// <code>if (Test-IsNableRunner) { Write-Host 'Running under N-able' }</code>
/// Conditionally adjusts output based on the detected host environment.
/// </example>
[Cmdlet("Test", "IsNableRunner")]
public sealed class TestIsNableRunnerCommand : PSCmdlet {
    protected override void ProcessRecord() {
        var leaf = EnvironmentRuntime.GetWindowTitleLeaf(this);

        this.WriteObject(
            !string.IsNullOrEmpty(leaf)
            && string.Equals(leaf, "fmplugin.exe", StringComparison.OrdinalIgnoreCase));
    }
}
