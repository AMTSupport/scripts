// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections.Generic;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using AMT.PowerShell.Common.Commands.PackageManager;

namespace AMT.PowerShell.Common.Tests.Commands.PackageManager;

[TestFixture]
[NonParallelizable]
public sealed class PackageManagerCommandTests {
    [TearDown]
    public void TearDown() {
        PackageManagerOperations.OsEnvironmentOverride = null;
        PackageManagerOperations.ProcessRunnerOverride = null;
        PackageManagerOperations.ExecutableExistsOverride = null;
    }

    // ── GetExecutable path construction ──────────────────────────────────────

    [Test]
    public void GetExecutable_ReturnsAbsolutePath_ForChocolatey() {
        // Bug: Path.Combine("C:", "ProgramData\...") = "C:ProgramData\..." (drive-relative).
        // Fix: explicit backslash gives "C:\ProgramData\..." (absolute).
        var result = PackageManagerOperations.GetExecutable(PackageManagerKind.Chocolatey);
        var colonIdx = result.IndexOf(':');

        Assert.Multiple(() => {
            Assert.That(result, Does.EndWith("choco.exe"));
            // Character immediately after the drive colon must be a separator.
            Assert.That(colonIdx, Is.GreaterThanOrEqualTo(0));
            Assert.That(result[colonIdx + 1], Is.EqualTo('\\').Or.EqualTo('/'),
                $"Expected path separator after drive colon, got: '{result}'");
        });
    }

    // ── DetectManager ────────────────────────────────────────────────────────

    [Test]
    public void DetectManager_ReturnsChocolatey_WhenWindowsNTAndExePresent() {
        PackageManagerOperations.OsEnvironmentOverride = () => "Windows_NT";
        PackageManagerOperations.ExecutableExistsOverride = _ => true;
        Assert.That(PackageManagerOperations.DetectManager(), Is.EqualTo(PackageManagerKind.Chocolatey));
    }

    [Test]
    public void DetectManager_ReturnsUnsupported_WhenExeAbsent() {
        // Windows OS but Chocolatey not installed — must not claim support.
        PackageManagerOperations.OsEnvironmentOverride = () => "Windows_NT";
        PackageManagerOperations.ExecutableExistsOverride = _ => false;
        Assert.That(PackageManagerOperations.DetectManager(), Is.EqualTo(PackageManagerKind.Unsupported));
    }

    [Test]
    public void DetectManager_ReturnsUnsupported_WhenOsIsNotWindowsNT() {
        PackageManagerOperations.OsEnvironmentOverride = () => "Linux";
        Assert.That(PackageManagerOperations.DetectManager(), Is.EqualTo(PackageManagerKind.Unsupported));
    }

    [Test]
    public void DetectManager_ReturnsUnsupported_WhenOsEnvIsNull() {
        PackageManagerOperations.OsEnvironmentOverride = () => null;
        Assert.That(PackageManagerOperations.DetectManager(), Is.EqualTo(PackageManagerKind.Unsupported));
    }

    // ── IsInstalled ──────────────────────────────────────────────────────────

    [Test]
    public void IsInstalled_ReturnsTrue_WhenOutputContainsNameVersionPipe() {
        PackageManagerOperations.ProcessRunnerOverride = (_, _) => (0, "git|2.46.0");
        Assert.That(PackageManagerOperations.IsInstalled(PackageManagerKind.Chocolatey, "git"), Is.True);
    }

    [Test]
    public void IsInstalled_ReturnsFalse_WhenOutputEmptyAndExitZero() {
        // choco returns exit 0 with empty output when package not installed.
        PackageManagerOperations.ProcessRunnerOverride = (_, _) => (0, string.Empty);
        Assert.That(PackageManagerOperations.IsInstalled(PackageManagerKind.Chocolatey, "absent-pkg"), Is.False);
    }

    [Test]
    public void IsInstalled_ReturnsFalse_WhenOutputContainsDifferentPackage() {
        // Guard against prefix false-positive: "git-lfs|3.0" must not match "git".
        PackageManagerOperations.ProcessRunnerOverride = (_, _) => (0, "git-lfs|3.0.0");
        Assert.That(PackageManagerOperations.IsInstalled(PackageManagerKind.Chocolatey, "git"), Is.False);
    }

    [Test]
    public void IsInstalled_ReturnsFalse_WhenProcessExitsNonZero() {
        PackageManagerOperations.ProcessRunnerOverride = (_, _) => (1, string.Empty);
        Assert.That(PackageManagerOperations.IsInstalled(PackageManagerKind.Chocolatey, "not-installed"), Is.False);
    }

    // ── Test-ManagedPackage cmdlet ───────────────────────────────────────────

    [Test]
    public void TestManagedPackage_ReturnsTrue_WhenPackageInstalled() {
        PackageManagerOperations.OsEnvironmentOverride = () => "Windows_NT";
        PackageManagerOperations.ExecutableExistsOverride = _ => true;
        PackageManagerOperations.ProcessRunnerOverride = (_, _) => (0, "git|2.46.0");

        var result = InvokeSingle<bool>("Test-ManagedPackage", ("PackageName", "git"));
        Assert.That(result, Is.True);
    }

    [Test]
    public void TestManagedPackage_ReturnsFalse_WhenPackageNotInstalled() {
        PackageManagerOperations.OsEnvironmentOverride = () => "Windows_NT";
        PackageManagerOperations.ExecutableExistsOverride = _ => true;
        PackageManagerOperations.ProcessRunnerOverride = (_, _) => (0, string.Empty);

        var result = InvokeSingle<bool>("Test-ManagedPackage", ("PackageName", "absent-pkg"));
        Assert.That(result, Is.False);
    }

    [Test]
    public void TestManagedPackage_WritesError_WhenUnsupportedPlatform() {
        PackageManagerOperations.OsEnvironmentOverride = () => "Linux";

        var invocation = InvokeCommand("Test-ManagedPackage", ("PackageName", "git"));
        Assert.Multiple(() => {
            Assert.That(invocation.HadErrors, Is.True);
            Assert.That(invocation.Results, Is.Empty);
        });
    }

    [Test]
    public void TestManagedPackage_WritesError_WhenWindowsButExeAbsent() {
        PackageManagerOperations.OsEnvironmentOverride = () => "Windows_NT";
        PackageManagerOperations.ExecutableExistsOverride = _ => false;

        var invocation = InvokeCommand("Test-ManagedPackage", ("PackageName", "git"));
        Assert.Multiple(() => {
            Assert.That(invocation.HadErrors, Is.True);
            Assert.That(invocation.Results, Is.Empty);
        });
    }

    // ── Install-ManagedPackage cmdlet ────────────────────────────────────────

    [Test]
    public void InstallManagedPackage_RunsInstall_WhenManagerSupported() {
        PackageManagerOperations.OsEnvironmentOverride = () => "Windows_NT";
        PackageManagerOperations.ExecutableExistsOverride = _ => true;
        string? capturedPkg = null;
        PackageManagerOperations.ProcessRunnerOverride = (_, args) => {
            capturedPkg = args[^1];
            return (0, string.Empty);
        };

        var invocation = InvokeCommand("Install-ManagedPackage", ("PackageName", "git"));
        Assert.Multiple(() => {
            Assert.That(invocation.HadErrors, Is.False);
            Assert.That(capturedPkg, Is.EqualTo("git"));
        });
    }

    [Test]
    public void InstallManagedPackage_IncludesChecksumArgs_WhenSha256Provided() {
        PackageManagerOperations.OsEnvironmentOverride = () => "Windows_NT";
        PackageManagerOperations.ExecutableExistsOverride = _ => true;
        string[]? capturedArgs = null;
        PackageManagerOperations.ProcessRunnerOverride = (_, args) => {
            capturedArgs = args;
            return (0, string.Empty);
        };

        InvokeCommand(
            "Install-ManagedPackage",
            ("PackageName", "googlechrome"),
            ("Sha256", "abc123deadbeef"));

        Assert.Multiple(() => {
            Assert.That(capturedArgs, Is.Not.Null);
            Assert.That(capturedArgs, Does.Contain("--checksum"));
            Assert.That(capturedArgs, Does.Contain("abc123deadbeef"));
            Assert.That(capturedArgs, Does.Contain("--checksum-type"));
            Assert.That(capturedArgs, Does.Contain("sha256"));
        });
    }

    [Test]
    public void InstallManagedPackage_OmitsChecksumArgs_WhenSha256NotProvided() {
        PackageManagerOperations.OsEnvironmentOverride = () => "Windows_NT";
        PackageManagerOperations.ExecutableExistsOverride = _ => true;
        string[]? capturedArgs = null;
        PackageManagerOperations.ProcessRunnerOverride = (_, args) => {
            capturedArgs = args;
            return (0, string.Empty);
        };

        InvokeCommand("Install-ManagedPackage", ("PackageName", "git"));

        Assert.That(capturedArgs, Does.Not.Contain("--checksum"));
    }

    [Test]
    public void InstallManagedPackage_AcceptsSha256Parameter_WhenBound() {
        // Verifies PowerShell parameter binding: -Sha256 accepted without error.
        PackageManagerOperations.OsEnvironmentOverride = () => "Windows_NT";
        PackageManagerOperations.ExecutableExistsOverride = _ => true;
        PackageManagerOperations.ProcessRunnerOverride = (_, _) => (0, string.Empty);

        var invocation = InvokeCommand(
            "Install-ManagedPackage",
            ("PackageName", "git"),
            ("Sha256", "deadbeef1234"));

        Assert.That(invocation.HadErrors, Is.False);
    }

    [Test]
    public void InstallManagedPackage_SkipsInstall_WhenWhatIf() {
        // SupportsShouldProcess + PSCmdlet: -WhatIf causes ShouldProcess to return false.
        PackageManagerOperations.OsEnvironmentOverride = () => "Windows_NT";
        PackageManagerOperations.ExecutableExistsOverride = _ => true;
        var installCalled = false;
        PackageManagerOperations.ProcessRunnerOverride = (_, _) => {
            installCalled = true;
            return (0, string.Empty);
        };

        var invocation = InvokeCommand(
            "Install-ManagedPackage",
            ("PackageName", "git"),
            ("WhatIf", true));

        Assert.Multiple(() => {
            Assert.That(invocation.HadErrors, Is.False);
            Assert.That(installCalled, Is.False);
        });
    }

    [Test]
    public void InstallManagedPackage_WritesError_WhenUnsupportedPlatform() {
        PackageManagerOperations.OsEnvironmentOverride = () => "Linux";

        var invocation = InvokeCommand("Install-ManagedPackage", ("PackageName", "git"));
        Assert.That(invocation.HadErrors, Is.True);
    }

    [Test]
    public void InstallManagedPackage_WritesError_WhenNoFailAndExitNonZero() {
        PackageManagerOperations.OsEnvironmentOverride = () => "Windows_NT";
        PackageManagerOperations.ExecutableExistsOverride = _ => true;
        PackageManagerOperations.ProcessRunnerOverride = (_, _) => (1, "fail");

        var invocation = InvokeCommand(
            "Install-ManagedPackage",
            ("PackageName", "bad-pkg"),
            ("NoFail", true));

        Assert.That(invocation.HadErrors, Is.True);
    }

    // ── Uninstall-ManagedPackage cmdlet ──────────────────────────────────────

    [Test]
    public void UninstallManagedPackage_RunsUninstall_WhenManagerSupported() {
        PackageManagerOperations.OsEnvironmentOverride = () => "Windows_NT";
        PackageManagerOperations.ExecutableExistsOverride = _ => true;
        var cmdCalled = false;
        PackageManagerOperations.ProcessRunnerOverride = (_, args) => {
            cmdCalled = args[0] == "uninstall";
            return (0, string.Empty);
        };

        var invocation = InvokeCommand("Uninstall-ManagedPackage", ("PackageName", "git"));
        Assert.That(invocation.HadErrors, Is.False);
        Assert.That(cmdCalled, Is.True);
    }

    [Test]
    public void UninstallManagedPackage_WritesError_WhenUnsupportedPlatform() {
        PackageManagerOperations.OsEnvironmentOverride = () => "Linux";

        var invocation = InvokeCommand("Uninstall-ManagedPackage", ("PackageName", "git"));
        Assert.That(invocation.HadErrors, Is.True);
    }

    // ── Update-ManagedPackage cmdlet ─────────────────────────────────────────

    [Test]
    public void UpdateManagedPackage_RunsUpdate_WhenManagerSupported() {
        PackageManagerOperations.OsEnvironmentOverride = () => "Windows_NT";
        PackageManagerOperations.ExecutableExistsOverride = _ => true;
        var cmdCalled = false;
        PackageManagerOperations.ProcessRunnerOverride = (_, args) => {
            cmdCalled = args[0] == "upgrade";
            return (0, string.Empty);
        };

        var invocation = InvokeCommand("Update-ManagedPackage", ("PackageName", "git"));
        Assert.That(invocation.HadErrors, Is.False);
        Assert.That(cmdCalled, Is.True);
    }

    [Test]
    public void UpdateManagedPackage_WritesError_WhenUnsupportedPlatform() {
        PackageManagerOperations.OsEnvironmentOverride = () => "Linux";

        var invocation = InvokeCommand("Update-ManagedPackage", ("PackageName", "git"));
        Assert.That(invocation.HadErrors, Is.True);
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private static T InvokeSingle<T>(string commandName, params (string Name, object? Value)[] parameters) {
        var invocation = InvokeCommand(commandName, parameters);
        Assert.That(invocation.Results, Has.Count.EqualTo(1));
        Assert.That(invocation.Results[0].BaseObject, Is.TypeOf<T>());
        return (T)invocation.Results[0].BaseObject;
    }

    private static CommandResult InvokeCommand(string commandName, params (string Name, object? Value)[] parameters) {
        var iss = InitialSessionState.CreateDefault2();
        iss.Commands.Add(new SessionStateCmdletEntry("Test-ManagedPackage", typeof(TestManagedPackageCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Install-ManagedPackage", typeof(InstallManagedPackageCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Uninstall-ManagedPackage", typeof(UninstallManagedPackageCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Update-ManagedPackage", typeof(UpdateManagedPackageCommand), null));

        using var runspace = RunspaceFactory.CreateRunspace(iss);
        runspace.Open();

        using var ps = System.Management.Automation.PowerShell.Create();
        ps.Runspace = runspace;
        ps.AddCommand(commandName);

        foreach (var (name, value) in parameters) {
            ps.AddParameter(name, value);
        }

        var results = ps.Invoke();
        var errors = ps.Streams.Error.Select(e => e.ToString()).ToArray();
        return new CommandResult(results, ps.HadErrors, errors);
    }

    private sealed record CommandResult(
        IReadOnlyList<PSObject> Results,
        bool HadErrors,
        IReadOnlyList<string> Errors);
}
