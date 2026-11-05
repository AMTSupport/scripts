// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation;
using System.Management.Automation.Runspaces;
using AMT.PowerShell.Common.Commands.Assert;
using NUnitAssert = NUnit.Framework.Assert;

namespace AMT.PowerShell.Common.Tests.Commands.AssertCmdlets;

[TestFixture]
[NonParallelizable]
public sealed class AssertCommandTests {
    [Test]
    public void AssertNotNull_Throws_WhenObjectIsNull() {
        NUnitAssert.That(
            () => InvokeCommand(
                "Assert-NotNull",
                typeof(AssertNotNullCommand),
                ("Object", null)),
            Throws.TypeOf<CmdletInvocationException>());
    }

    [Test]
    public void AssertNotNull_DoesNotThrow_WhenObjectIsNotNull() {
        var invocation = InvokeCommand(
            "Assert-NotNull",
            typeof(AssertNotNullCommand),
            ("Object", "value"));

        NUnitAssert.That(invocation.HadErrors, Is.False);
    }

    [Test]
    public void AssertEqual_DoesNotThrow_ForCaseInsensitiveStringMatch() {
        var invocation = InvokeCommand(
            "Assert-Equal",
            typeof(AssertEqualCommand),
            ("Object", "foo"),
            ("Expected", "FOO"));

        NUnitAssert.That(invocation.HadErrors, Is.False);
    }

    [Test]
    public void AssertEqual_Throws_WhenValuesDiffer() {
        NUnitAssert.That(
            () => InvokeCommand(
                "Assert-Equal",
                typeof(AssertEqualCommand),
                ("Object", "foo"),
                ("Expected", "bar")),
            Throws.TypeOf<CmdletInvocationException>());
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

        powerShell.Invoke();
        var errors = powerShell.Streams.Error.Select(error => error.ToString()).ToArray();

        return new CommandInvocationResult(powerShell.HadErrors, errors);
    }

    private sealed record CommandInvocationResult(bool HadErrors, IReadOnlyList<string> Errors);
}
