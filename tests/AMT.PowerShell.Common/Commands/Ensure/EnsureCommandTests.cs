// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Runtime.InteropServices;
using AMT.PowerShell.Common.Commands.Ensure;

namespace AMT.PowerShell.Common.Tests.Commands.Ensure;

[TestFixture]
[NonParallelizable]
public sealed class EnsureCommandTests {
    [TearDown]
    public void TearDown() {
        InvokeEnsureNetworkCommand.NetworkAvailableOverride = null;
        InvokeEnsureNetworkCommand.ProcessRunnerOverride = null;
        InvokeEnsureNetworkCommand.DelayMsOverride = null;
    }

    [Test]
    public void InvokeEnsureAdministrator_DoesNotThrow_OnNonWindows() {
        Assume.That(
            !RuntimeInformation.IsOSPlatform(OSPlatform.Windows),
            "This test verifies the non-Windows skip behaviour.");

        var result = InvokeCommand("Invoke-EnsureAdministrator", typeof(InvokeEnsureAdministratorCommand));

        Assert.Multiple(() => {
            Assert.That(result.HadErrors, Is.False);
            Assert.That(result.Output, Is.Empty);
        });
    }

    [Test]
    public void InvokeEnsureUser_DoesNotThrow_OnNonWindows() {
        Assume.That(
            !RuntimeInformation.IsOSPlatform(OSPlatform.Windows),
            "This test verifies the non-Windows skip behaviour.");

        var result = InvokeCommand("Invoke-EnsureUser", typeof(InvokeEnsureUserCommand));

        Assert.Multiple(() => {
            Assert.That(result.HadErrors, Is.False);
            Assert.That(result.Output, Is.Empty);
        });
    }

    [Test]
    public void InvokeEnsureNetwork_ReturnsTrue_WhenDisconnectedAndConnectSucceeds() {
        // First call = initial check (false); all subsequent = polling (true after connect).
        var callCount = 0;
        InvokeEnsureNetworkCommand.NetworkAvailableOverride = () => callCount++ > 0;
        InvokeEnsureNetworkCommand.ProcessRunnerOverride = (_, _) => 0;
        InvokeEnsureNetworkCommand.DelayMsOverride = _ => { };

        var result = InvokeCommand(
            "Invoke-EnsureNetwork",
            typeof(InvokeEnsureNetworkCommand),
            ("Name", "TestNetwork"));

        Assert.Multiple(() => {
            Assert.That(result.HadErrors, Is.False);
            Assert.That(result.Output, Has.Count.EqualTo(1));
            Assert.That(result.Output[0].BaseObject, Is.TypeOf<bool>());
            Assert.That((bool)result.Output[0].BaseObject, Is.True);
        });
    }

    [Test]
    public void InvokeEnsureNetwork_ThrowsNoNetwork_WhenDisconnectedAndConnectFails() {
        // Connectivity never recovers, but netsh "succeeds" — same as legacy timeout path.
        InvokeEnsureNetworkCommand.NetworkAvailableOverride = () => false;
        InvokeEnsureNetworkCommand.ProcessRunnerOverride = (_, _) => 0;
        InvokeEnsureNetworkCommand.DelayMsOverride = _ => { };

        try {
            InvokeCommand(
                "Invoke-EnsureNetwork",
                typeof(InvokeEnsureNetworkCommand),
                ("Name", "TestNetwork"));
            Assert.Fail("Expected CmdletInvocationException was not thrown.");
        } catch (CmdletInvocationException ex) {
            Assert.That(
                ex.ErrorRecord.FullyQualifiedErrorId,
                Does.StartWith("AMT.Ensure.NoNetwork"));
        }
    }

    [Test]
    public void InvokeEnsureNetwork_AcceptsNameParameter_BindsWithoutError() {
        InvokeEnsureNetworkCommand.NetworkAvailableOverride = () => true;

        var result = InvokeCommand(
            "Invoke-EnsureNetwork",
            typeof(InvokeEnsureNetworkCommand),
            ("Name", "TestNetwork"));

        Assert.That(result.HadErrors, Is.False);
    }

    [Test]
    public void InvokeEnsureNetwork_AcceptsNameAndPassword_BindsWithoutError() {
        InvokeEnsureNetworkCommand.NetworkAvailableOverride = () => true;

        var password = new System.Security.SecureString();
        foreach (var c in "TestPass") { password.AppendChar(c); }
        password.MakeReadOnly();

        var result = InvokeCommand(
            "Invoke-EnsureNetwork",
            typeof(InvokeEnsureNetworkCommand),
            ("Name", "TestNetwork"),
            ("Password", (object?)password));

        Assert.That(result.HadErrors, Is.False);
    }

    [Test]
    public void InvokeEnsureNetwork_ReturnsFalse_WhenNetworkAvailable() {
        InvokeEnsureNetworkCommand.NetworkAvailableOverride = () => true;

        var result = InvokeCommand("Invoke-EnsureNetwork", typeof(InvokeEnsureNetworkCommand));

        Assert.Multiple(() => {
            Assert.That(result.HadErrors, Is.False);
            Assert.That(result.Output, Has.Count.EqualTo(1));
            Assert.That(result.Output[0].BaseObject, Is.TypeOf<bool>());
            Assert.That((bool)result.Output[0].BaseObject, Is.False);
        });
    }

    [Test]
    public void InvokeEnsureNetwork_ThrowsTerminatingError_WhenNoNetwork() {
        InvokeEnsureNetworkCommand.NetworkAvailableOverride = () => false;

        Assert.Throws<CmdletInvocationException>(() =>
            InvokeCommand("Invoke-EnsureNetwork", typeof(InvokeEnsureNetworkCommand)));
    }

    [Test]
    public void InvokeEnsureNetwork_ErrorId_WhenNoNetwork() {
        InvokeEnsureNetworkCommand.NetworkAvailableOverride = () => false;

        try {
            InvokeCommand("Invoke-EnsureNetwork", typeof(InvokeEnsureNetworkCommand));
            Assert.Fail("Expected CmdletInvocationException was not thrown.");
        } catch (CmdletInvocationException ex) {
            // FullyQualifiedErrorId appends the cmdlet class name: "ErrorId,ClassName".
            Assert.That(
                ex.ErrorRecord.FullyQualifiedErrorId,
                Does.StartWith("AMT.Ensure.NoNetwork"));
        }
    }

    private static CommandInvocationResult InvokeCommand(
            string commandName,
            Type cmdletType,
            params (string Name, object? Value)[] parameters) {
        var initialSessionState = InitialSessionState.CreateDefault2();
        initialSessionState.Commands.Add(
            new SessionStateCmdletEntry(commandName, cmdletType, helpFileName: null));

        using var runspace = RunspaceFactory.CreateRunspace(initialSessionState);
        runspace.Open();

        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddCommand(commandName);

        foreach (var (name, value) in parameters) {
            powerShell.AddParameter(name, value);
        }

        var output = new Collection<PSObject>();

        try {
            powerShell.Invoke(input: null, output);
        } catch (CmdletInvocationException) {
            throw;
        }

        return new CommandInvocationResult(output, [.. powerShell.Streams.Error], powerShell.HadErrors);
    }

    private sealed record CommandInvocationResult(
        Collection<PSObject> Output,
        IReadOnlyList<ErrorRecord> Errors,
        bool HadErrors);
}
