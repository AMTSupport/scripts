// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.PackageManager;

/// <summary>Installs a package using the detected system package manager.</summary>
/// <remarks>
/// Detects the available package manager (e.g., Chocolatey, Winget) and installs the named
/// package. Uses ShouldProcess to support -WhatIf and -Confirm.
/// Terminates on failure unless -NoFail is specified.
/// </remarks>
/// <example>
/// <code>Install-ManagedPackage -PackageName 'git'</code>
/// Installs the git package using the available package manager.
/// </example>
/// <example>
/// <code>Install-ManagedPackage -PackageName 'notepadplusplus' -Sha256 'abc123...' -NoFail</code>
/// Installs Notepad++ with SHA256 verification; writes a non-terminating error on failure.
/// </example>
[Cmdlet(VerbsLifecycle.Install, "ManagedPackage", SupportsShouldProcess = true)]
public sealed class InstallManagedPackageCommand : PSCmdlet {
    /// <summary>The name of the package to install.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string PackageName { get; set; } = string.Empty;

    /// <summary>
    /// When set, writes a non-terminating error instead of terminating if installation fails.
    /// </summary>
    [Parameter]
    public SwitchParameter NoFail { get; set; }

    /// <summary>Expected SHA256 hash of the downloaded package; used for integrity validation.</summary>
    [Parameter]
    [ValidateNotNullOrEmpty]
    public string? Sha256 { get; set; }

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

        if (!this.ShouldProcess(this.PackageName, "Install package")) {
            return;
        }

        var (exitCode, output) = PackageManagerOperations.Install(manager, this.PackageName, this.Sha256);
        if (exitCode != 0) {
            var error = new ErrorRecord(
                new System.InvalidOperationException($"Package installation failed (exit {exitCode}): {output}"),
                "PackageInstallFailed",
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
