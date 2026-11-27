// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation;
using System.Management.Automation.Runspaces;

using AMT.PowerShell.Common.Commands.Windows;

namespace AMT.PowerShell.Common.Tests.Commands.Windows;

[TestFixture]
[NonParallelizable]
public sealed class WindowsTimeCommandTests {
    [Test]
    public void GetLastSyncTime_ReturnsUnixEpoch_WhenW32tmUnavailable() {
        var previousPath = Environment.GetEnvironmentVariable("PATH");

        try {
            Environment.SetEnvironmentVariable("PATH", string.Empty);

            var invocation = InvokeCommand(
                "Get-LastSyncTime",
                typeof(GetLastSyncTimeCommand));

            Assert.Multiple(() => {
                Assert.That(invocation.HadErrors, Is.False);
                Assert.That(invocation.Results, Has.Count.EqualTo(1));
                Assert.That(invocation.Results[0].BaseObject, Is.TypeOf<DateTime>());
                Assert.That((DateTime)invocation.Results[0].BaseObject, Is.EqualTo(new DateTime(1970, 1, 1)));
            });
        } finally {
            Environment.SetEnvironmentVariable("PATH", previousPath);
        }
    }

    [Test]
    public void GetLastSyncTime_ReturnsUnixEpoch_WhenParseFails() {
        var value = GetLastSyncTimeCommand.ParseLastSyncTime("not-w32tm-output");

        Assert.That(value, Is.EqualTo(new DateTime(1970, 1, 1)));
    }

    [Test]
    public void SyncTime_ReturnsFalse_WhenW32tmUnavailable() {
        var previousPath = Environment.GetEnvironmentVariable("PATH");

        try {
            Environment.SetEnvironmentVariable("PATH", string.Empty);

            var invocation = InvokeCommand(
                "Sync-Time",
                typeof(SyncTimeCommand),
                ("Threshold", TimeSpan.FromDays(1)));

            Assert.Multiple(() => {
                Assert.That(invocation.HadErrors, Is.False);
                Assert.That(invocation.Results, Has.Count.EqualTo(1));
                Assert.That(invocation.Results[0].BaseObject, Is.TypeOf<bool>());
                Assert.That((bool)invocation.Results[0].BaseObject, Is.False);
            });
        } finally {
            Environment.SetEnvironmentVariable("PATH", previousPath);
        }
    }

    private static CommandInvocationResult InvokeCommand(string commandName, Type cmdletType, params (string Name, object? Value)[] parameters) {
        var initialSessionState = InitialSessionState.CreateDefault2();
        initialSessionState.Commands.Add(new SessionStateCmdletEntry(commandName, cmdletType, helpFileName: null));

        using var runspace = RunspaceFactory.CreateRunspace(initialSessionState);
        runspace.Open();

        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddCommand(commandName);

        foreach (var (name, value) in parameters) {
            powerShell.AddParameter(name, value);
        }

        var results = powerShell.Invoke();
        var errors = powerShell.Streams.Error.Select(error => error.ToString()).ToArray();

        return new CommandInvocationResult(results, powerShell.HadErrors, errors);
    }

    private sealed record CommandInvocationResult(IReadOnlyList<PSObject> Results, bool HadErrors, IReadOnlyList<string> Errors);
}
