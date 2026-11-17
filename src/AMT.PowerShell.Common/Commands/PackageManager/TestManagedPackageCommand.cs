// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.PackageManager;

/// <summary>Tests whether a package is installed via the detected package manager.</summary>
/// <remarks>
/// Detects the available package manager and queries it for the named package.
/// Returns <see langword="true"/> if the package is installed, <see langword="false"/> otherwise.
/// </remarks>
/// <example>
/// <code>Test-ManagedPackage -PackageName 'git'</code>
/// Returns $true if git is installed, $false otherwise.
/// </example>
[Cmdlet(VerbsDiagnostic.Test, "ManagedPackage")]
[OutputType(typeof(bool))]
public sealed class TestManagedPackageCommand : Cmdlet {
    /// <summary>The name of the package to test for installation.</summary>
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

        this.WriteObject(PackageManagerOperations.IsInstalled(manager, this.PackageName));
    }
}
