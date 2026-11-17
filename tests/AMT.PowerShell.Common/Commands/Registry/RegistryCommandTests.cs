// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Runtime.InteropServices;
using AMT.PowerShell.Common.Commands.Registry;

namespace AMT.PowerShell.Common.Tests.Commands.Registry;

[TestFixture]
[NonParallelizable]
public sealed class RegistryCommandTests {
    private const string UnsupportedErrorId = "AMT.Registry.PlatformNotSupported";

    // --- Test-RegistryKey ---

    [Test]
    public void TestRegistryKey_WritesUnsupportedError_OnNonWindows() {
        Assume.That(
            !RuntimeInformation.IsOSPlatform(OSPlatform.Windows),
            "This test verifies the non-Windows error path.");

        var result = InvokeRegistryCommand("Test-RegistryKey", ps => {
            ps.AddParameter("Path", @"HKLM:\SOFTWARE\Test");
            ps.AddParameter("Key", "TestValue");
        }, typeof(TestRegistryKeyCommand));

        Assert.Multiple(() => {
            Assert.That(result.HadErrors, Is.True);
            Assert.That(result.Output, Is.Empty);
            // FullyQualifiedErrorId appends the cmdlet class name: "ErrorId,ClassName".
            Assert.That(result.Errors[0].FullyQualifiedErrorId, Does.StartWith(UnsupportedErrorId));
            Assert.That(result.Errors[0].CategoryInfo.Category, Is.EqualTo(ErrorCategory.NotImplemented));
        });
    }

    // --- Get-RegistryKey ---

    [Test]
    public void GetRegistryKey_WritesUnsupportedError_OnNonWindows() {
        Assume.That(
            !RuntimeInformation.IsOSPlatform(OSPlatform.Windows),
            "This test verifies the non-Windows error path.");

        var result = InvokeRegistryCommand("Get-RegistryKey", ps => {
            ps.AddParameter("Path", @"HKLM:\SOFTWARE\Test");
            ps.AddParameter("Key", "TestValue");
        }, typeof(GetRegistryKeyCommand));

        Assert.Multiple(() => {
            Assert.That(result.HadErrors, Is.True);
            Assert.That(result.Output, Is.Empty);
            Assert.That(result.Errors[0].FullyQualifiedErrorId, Does.StartWith(UnsupportedErrorId));
        });
    }

    // --- Set-RegistryKey ---

    [Test]
    public void SetRegistryKey_WritesUnsupportedError_OnNonWindows() {
        Assume.That(
            !RuntimeInformation.IsOSPlatform(OSPlatform.Windows),
            "This test verifies the non-Windows error path.");

        var result = InvokeRegistryCommand("Set-RegistryKey", ps => {
            ps.AddParameter("Path", @"HKLM:\SOFTWARE\Test");
            ps.AddParameter("Key", "TestValue");
            ps.AddParameter("Value", "data");
            ps.AddParameter("Kind", RegistryValueKind.String);
        }, typeof(SetRegistryKeyCommand));

        Assert.Multiple(() => {
            Assert.That(result.HadErrors, Is.True);
            Assert.That(result.Errors[0].FullyQualifiedErrorId, Does.StartWith(UnsupportedErrorId));
        });
    }

    // --- Remove-RegistryKey ---

    [Test]
    public void RemoveRegistryKey_WritesUnsupportedError_OnNonWindows() {
        Assume.That(
            !RuntimeInformation.IsOSPlatform(OSPlatform.Windows),
            "This test verifies the non-Windows error path.");

        var result = InvokeRegistryCommand("Remove-RegistryKey", ps => {
            ps.AddParameter("Path", @"HKLM:\SOFTWARE\Test");
            ps.AddParameter("Key", "TestValue");
        }, typeof(RemoveRegistryKeyCommand));

        Assert.Multiple(() => {
            Assert.That(result.HadErrors, Is.True);
            Assert.That(result.Errors[0].FullyQualifiedErrorId, Does.StartWith(UnsupportedErrorId));
        });
    }

    // --- Invoke-OnEachUserHive ---

    [Test]
    public void InvokeOnEachUserHive_WritesUnsupportedError_OnNonWindows() {
        Assume.That(
            !RuntimeInformation.IsOSPlatform(OSPlatform.Windows),
            "This test verifies the non-Windows error path.");

        var result = InvokeRegistryCommand("Invoke-OnEachUserHive", ps => {
            ps.AddParameter("ScriptBlock", ScriptBlock.Create("param($Hive) $Hive.SID"));
        }, typeof(InvokeOnEachUserHiveCommand));

        Assert.Multiple(() => {
            Assert.That(result.HadErrors, Is.True);
            Assert.That(result.Output, Is.Empty);
            Assert.That(result.Errors[0].FullyQualifiedErrorId, Does.StartWith(UnsupportedErrorId));
            Assert.That(result.Errors[0].CategoryInfo.Category, Is.EqualTo(ErrorCategory.NotImplemented));
        });
    }

    // --- Helpers ---

    private static CommandInvocationResult InvokeRegistryCommand(
        string commandName,
        Action<System.Management.Automation.PowerShell> configure,
        Type cmdletType) {
        var initialSessionState = InitialSessionState.CreateDefault2();
        initialSessionState.Commands.Add(
            new SessionStateCmdletEntry(commandName, cmdletType, helpFileName: null));

        using var runspace = RunspaceFactory.CreateRunspace(initialSessionState);
        runspace.Open();

        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddCommand(commandName);
        configure(powerShell);

        var output = new Collection<PSObject>();
        RuntimeException? thrown = null;

        try {
            powerShell.Invoke(input: null, output);
        } catch (RuntimeException ex) {
            thrown = ex;
        }

        return new CommandInvocationResult(output, [.. powerShell.Streams.Error], powerShell.HadErrors, thrown);
    }

    private sealed record CommandInvocationResult(
        Collection<PSObject> Output,
        IReadOnlyList<ErrorRecord> Errors,
        bool HadErrors,
        RuntimeException? ThrownException);
}
