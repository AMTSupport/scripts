// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.PackageManager;

/// <summary>Updates a package to its latest version using the detected system package manager.</summary>
/// <remarks>
/// Detects the available package manager (e.g., Chocolatey, Winget) and updates the named
/// package. Uses ShouldProcess to support -WhatIf and -Confirm.
/// Writes a non-terminating error if the update fails.
/// </remarks>
/// <example>
/// <code>Update-ManagedPackage -PackageName 'git'</code>
/// Updates the git package to its latest available version.
/// </example>
[Cmdlet(VerbsData.Update, "ManagedPackage", SupportsShouldProcess = true)]
public sealed class UpdateManagedPackageCommand : PSCmdlet {
    /// <summary>The name of the package to update.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string PackageName { get; set; } = string.Empty;

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

        if (!this.ShouldProcess(this.PackageName, "Update package")) {
            return;
        }

        var (exitCode, output) = PackageManagerOperations.Update(manager, this.PackageName);
        if (exitCode != 0) {
            this.WriteError(new ErrorRecord(
                new System.InvalidOperationException($"Package update failed (exit {exitCode}): {output}"),
                "PackageUpdateFailed",
                ErrorCategory.InvalidOperation,
                this.PackageName));
        }
    }
}
