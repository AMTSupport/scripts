// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using AMT.PowerShell.Common.Commands.Scope;

namespace AMT.PowerShell.Common.Tests.Commands.Scope;

[TestFixture]
[NonParallelizable]
public sealed class ScopeCommandTests {
    // ── Stack behaviour ──────────────────────────────────────────────────

    [Test]
    public void EnterScope_PushesInvocationFrame() {
        using var runspace = CreateRunspace();
        var invocation = GetInvocationInfo(runspace, "Test-Scope");

        Invoke(runspace, "Enter-Scope", ("Invocation", invocation));

        Assert.Multiple(() => {
            Assert.That(ScopeStack.Count(runspace), Is.EqualTo(1));
            Assert.That(ScopeStack.TryPeek(runspace, out var frame), Is.True);
            Assert.That(frame!.Invocation.MyCommand!.Name, Is.EqualTo("Test-Scope"));
        });
    }

    [Test]
    public void EnterScope_WithoutInvocation_CapturesCallerFunctionName() {
        using var runspace = CreateRunspace();

        InvokeScript(runspace, "function Test-Caller { Enter-Scope }; Test-Caller");

        Assert.Multiple(() => {
            Assert.That(ScopeStack.Count(runspace), Is.EqualTo(1));
            Assert.That(ScopeStack.TryPeek(runspace, out var frame), Is.True);
            Assert.That(frame!.Invocation.MyCommand!.Name, Is.EqualTo("Test-Caller"));
        });
    }

    [Test]
    public void ExitScope_PopsLatestFrame() {
        using var runspace = CreateRunspace();

        Invoke(runspace, "Enter-Scope", ("Invocation", GetInvocationInfo(runspace, "First")));
        Invoke(runspace, "Enter-Scope", ("Invocation", GetInvocationInfo(runspace, "Second")));

        Invoke(runspace, "Exit-Scope");

        Assert.Multiple(() => {
            Assert.That(ScopeStack.Count(runspace), Is.EqualTo(1));
            Assert.That(ScopeStack.TryPeek(runspace, out var frame), Is.True);
            Assert.That(frame!.Invocation.MyCommand!.Name, Is.EqualTo("First"));
        });
    }

    [Test]
    public void ScopeStack_IsIsolatedPerRunspace() {
        using var runspaceA = CreateRunspace();
        using var runspaceB = CreateRunspace();

        Invoke(runspaceA, "Enter-Scope", ("Invocation", GetInvocationInfo(runspaceA, "A")));

        Assert.Multiple(() => {
            Assert.That(ScopeStack.Count(runspaceA), Is.EqualTo(1));
            Assert.That(ScopeStack.Count(runspaceB), Is.EqualTo(0));
        });
    }

    // ── Format-ScopeName ────────────────────────────────────────────────

    [Test]
    public void FormatScopeName_ReturnsSingleScope() {
        using var runspace = CreateRunspace();

        Invoke(runspace, "Enter-Scope", ("Invocation", GetInvocationInfo(runspace, "It")));

        var result = Invoke(runspace, "Format-ScopeName");

        Assert.That(result.Single().BaseObject, Is.EqualTo("It"));
    }

    [Test]
    public void FormatScopeName_ProducesEnterChain() {
        using var runspace = CreateRunspace();

        Invoke(runspace, "Enter-Scope", ("Invocation", GetInvocationInfo(runspace, "Describe")));
        Invoke(runspace, "Enter-Scope", ("Invocation", GetInvocationInfo(runspace, "Context")));
        Invoke(runspace, "Enter-Scope", ("Invocation", GetInvocationInfo(runspace, "It")));

        var result = Invoke(runspace, "Format-ScopeName");

        Assert.That(result.Single().BaseObject, Is.EqualTo("Describe > Context > It"));
    }

    [Test]
    public void FormatScopeName_ProducesExitChain() {
        using var runspace = CreateRunspace();

        Invoke(runspace, "Enter-Scope", ("Invocation", GetInvocationInfo(runspace, "Describe")));
        Invoke(runspace, "Enter-Scope", ("Invocation", GetInvocationInfo(runspace, "Context")));
        Invoke(runspace, "Enter-Scope", ("Invocation", GetInvocationInfo(runspace, "It")));

        var result = Invoke(runspace, "Format-ScopeName", ("IsExit", true));

        Assert.That(result.Single().BaseObject, Is.EqualTo("Describe > Context < It"));
    }

    [Test]
    public void FormatScopeName_SortsPreviousScopesDescending() {
        using var runspace = CreateRunspace();

        // Previous frames are sorted descending by name, not insertion order.
        Invoke(runspace, "Enter-Scope", ("Invocation", GetInvocationInfo(runspace, "Charlie")));
        Invoke(runspace, "Enter-Scope", ("Invocation", GetInvocationInfo(runspace, "Alpha")));
        Invoke(runspace, "Enter-Scope", ("Invocation", GetInvocationInfo(runspace, "Bravo")));

        var result = Invoke(runspace, "Format-ScopeName");

        Assert.That(result.Single().BaseObject, Is.EqualTo("Charlie > Alpha > Bravo"));
    }

    // ── Output parity ───────────────────────────────────────────────────

    [Test]
    public void EnterScope_Verbose_EmitsPrefixedScopeNameAndParameters() {
        using var runspace = CreateRunspace();

        var result = RunScript(runspace, """
            $VerbosePreference = 'Continue'
            function Test-Caller {
                param($Name, $Secret)
                Enter-Scope -IgnoreParams @('Secret') -ArgumentFormatter @{ Name = { 'formatted:' + $_ } }
            }
            Test-Caller -Name 'alice' -Secret 's3cret'
            """);

        Assert.That(result.Errors, Is.Empty);

        var messages = result.Information.Select(info => info.MessageData?.ToString() ?? string.Empty).ToList();

        Assert.That(messages, Has.Some.Contain("❯❯ Test-Caller"));
        Assert.That(messages, Has.Some.Contain("Name = formatted:alice"));
        Assert.That(messages, Has.None.Contain("Secret"));
    }

    [Test]
    public void EnterScope_PassThru_ReturnsFormattedMessage() {
        using var runspace = CreateRunspace();

        var result = RunScript(runspace, """
            $VerbosePreference = 'Continue'
            function Test-Caller { Enter-Scope -PassThru }
            Test-Caller
            """);

        Assert.That(result.Errors, Is.Empty);
        Assert.That(result.Output, Has.Count.EqualTo(1));
        Assert.That(result.Output[0].BaseObject, Is.EqualTo("❯❯ Test-Caller"));
    }

    [Test]
    public void ExitScope_Verbose_EmitsPrefixedScopeNameExecutionTimeAndReturnValue() {
        using var runspace = CreateRunspace();

        var result = RunScript(runspace, """
            $VerbosePreference = 'Continue'
            function Test-Caller {
                Enter-Scope
                Exit-Scope -ReturnValue 'done'
            }
            Test-Caller
            """);

        Assert.That(result.Errors, Is.Empty);

        var messages = result.Information.Select(info => info.MessageData?.ToString() ?? string.Empty).ToList();

        Assert.That(messages, Has.Some.Contain("❮❮ Test-Caller"));
        Assert.That(messages, Has.Some.Contain("Execution Time:"));
        Assert.That(messages, Has.Some.Contain("done"));
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private static Runspace CreateRunspace() {
        var initialSessionState = InitialSessionState.CreateDefault2();
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Enter-Scope", typeof(EnterScopeCommand), null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Exit-Scope", typeof(ExitScopeCommand), null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Format-ScopeName", typeof(FormatScopeNameCommand), null));

        var runspace = RunspaceFactory.CreateRunspace(initialSessionState);
        runspace.Open();
        return runspace;
    }

    private static InvocationInfo GetInvocationInfo(Runspace runspace, string commandName) {
        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddScript($"function {commandName} {{ $MyInvocation }}; {commandName}");

        var results = powerShell.Invoke();

        Assert.That(results, Has.Count.EqualTo(1));
        return (InvocationInfo)results[0].BaseObject;
    }

    private static void InvokeScript(Runspace runspace, string script) {
        var result = RunScript(runspace, script);

        if (result.Errors.Count > 0 || result.ThrownException is not null) {
            var errors = string.Join(Environment.NewLine, result.Errors.Select(error => error.ToString()));
            throw new AssertionException($"Script failed:{Environment.NewLine}{errors}");
        }
    }

    private static Collection<PSObject> Invoke(Runspace runspace, string commandName, params (string Name, object? Value)[] parameters) {
        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddCommand(commandName);

        foreach (var (name, value) in parameters) {
            powerShell.AddParameter(name, value);
        }

        var results = powerShell.Invoke();

        if (powerShell.HadErrors) {
            var errors = string.Join(
                Environment.NewLine,
                powerShell.Streams.Error.Select(error => error.ToString()));
            throw new AssertionException($"Command '{commandName}' failed:{Environment.NewLine}{errors}");
        }

        return results;
    }

    private static ScriptResult RunScript(Runspace runspace, string script) {
        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddScript(script);

        var output = new Collection<PSObject>();
        RuntimeException? thrown = null;

        try {
            powerShell.Invoke(null, output);
        } catch (RuntimeException exception) {
            thrown = exception;
        }

        return new ScriptResult(output, [.. powerShell.Streams.Information], [.. powerShell.Streams.Error], thrown);
    }

    private sealed record ScriptResult(
        Collection<PSObject> Output,
        IReadOnlyList<InformationRecord> Information,
        IReadOnlyList<ErrorRecord> Errors,
        RuntimeException? ThrownException);
}
