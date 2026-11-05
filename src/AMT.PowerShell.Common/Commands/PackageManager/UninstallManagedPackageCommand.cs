// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.PackageManager;

/// <summary>Uninstalls a package using the detected system package manager.</summary>
/// <remarks>
/// Detects the available package manager (e.g., Chocolatey, Winget) and removes the named
/// package. Uses ShouldProcess to support -WhatIf and -Confirm.
/// Terminates on failure unless -NoFail is specified.
/// </remarks>
/// <example>
/// <code>Uninstall-ManagedPackage -PackageName 'git'</code>
/// Uninstalls the git package using the available package manager.
/// </example>
/// <example>
/// <code>Uninstall-ManagedPackage -PackageName 'notepadplusplus' -NoFail</code>
/// Attempts uninstallation and writes a non-terminating error if it fails.
/// </example>
[Cmdlet(VerbsLifecycle.Uninstall, "ManagedPackage", SupportsShouldProcess = true)]
public sealed class UninstallManagedPackageCommand : PSCmdlet {
    /// <summary>The name of the package to uninstall.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string PackageName { get; set; } = string.Empty;

    /// <summary>
    /// When set, writes a non-terminating error instead of terminating if uninstallation fails.
    /// </summary>
    [Parameter]
    public SwitchParameter NoFail { get; set; }

    protected override void ProcessRecord() {
        var manager = PackageManagerOperations.DetectManager();
        if (manager == PackageManagerKind.Unsupported) {
            this.WriteError(new ErrorRecord(
                new System.NotSupportedException("No supported package manager found on this platform."),
                "UnsupportedPackageManager",
                ErrorCategory.NotImplemented,
                targetObject: null));
            return;
        }

        if (!this.ShouldProcess(this.PackageName, "Uninstall package")) {
            return;
        }

        var (exitCode, output) = PackageManagerOperations.Uninstall(manager, this.PackageName);
        if (exitCode != 0) {
            var error = new ErrorRecord(
                new System.InvalidOperationException($"Package uninstallation failed (exit {exitCode}): {output}"),
                "PackageUninstallFailed",
                ErrorCategory.InvalidOperation,
                this.PackageName);

            if (this.NoFail) {
                this.WriteError(error);
            } else {
                this.ThrowTerminatingError(error);
            }
        }
    }
}
