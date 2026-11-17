// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using AMT.PowerShell.Common.Commands.Exit;

namespace AMT.PowerShell.Common.Tests.Commands.Exit;

[TestFixture]
[NonParallelizable]
public sealed class ExitCommandTests {
    [Test]
    public void RegisterExitCode_ReturnsDeterministicReusableCode() {
        using var runspace = CreateRunspace();

        var first = Invoke(runspace, "Register-ExitCode", ("Description", "first description"));
        var again = Invoke(runspace, "Register-ExitCode", ("Description", "first description"));
        var second = Invoke(runspace, "Register-ExitCode", ("Description", "second description"));

        var firstCode = (int)first.Output.Single().BaseObject;
        var againCode = (int)again.Output.Single().BaseObject;
        var secondCode = (int)second.Output.Single().BaseObject;

        Assert.Multiple(() => {
            Assert.That(againCode, Is.EqualTo(firstCode));
            Assert.That(secondCode, Is.Not.EqualTo(firstCode));
            Assert.That(firstCode, Is.GreaterThanOrEqualTo(1001));
            Assert.That(secondCode, Is.GreaterThanOrEqualTo(1001));
        });
    }

    [Test]
    public void RegisterExitCode_ReusesCodeCaseInsensitively() {
        using var runspace = CreateRunspace();

        var lower = Invoke(runspace, "Register-ExitCode", ("Description", "Some Description"));
        var upper = Invoke(runspace, "Register-ExitCode", ("Description", "SOME DESCRIPTION"));

        Assert.That(
            (int)upper.Output.Single().BaseObject,
            Is.EqualTo((int)lower.Output.Single().BaseObject));
    }

    [Test]
    public void ExitStore_IsIsolatedPerRunspace() {
        using var runspaceA = CreateRunspace();
        using var runspaceB = CreateRunspace();

        Invoke(runspaceA, "Register-ExitHandler",
            ("Name", "handler"),
            ("ExitHandler", ScriptBlock.Create("{}")));

        Assert.Multiple(() => {
            Assert.That(ExitStore.Contains(runspaceA, "handler"), Is.True);
            Assert.That(ExitStore.Contains(runspaceB, "handler"), Is.False);
        });
    }

    [Test]
    public void InvokeHandlers_RunsEachHandlerOnce() {
        using var runspace = CreateRunspace();
        var markerFile = Path.GetTempFileName();

        try {
            Invoke(runspace, "Register-ExitHandler",
                ("Name", "once"),
                ("ExitHandler", CreateAppendScript(markerFile, "X")));

            Invoke(runspace, "Invoke-Handlers");
            Invoke(runspace, "Invoke-Handlers");

            Assert.That(File.ReadAllLines(markerFile), Is.EqualTo(new[] { "X" }));
        } finally {
            TryDeleteFile(markerFile);
        }
    }

    [Test]
    public void InvokeHandlers_RespectsFailureFilter() {
        using var runspace = CreateRunspace();
        var markerFile = Path.GetTempFileName();

        try {
            Invoke(runspace, "Register-ExitHandler",
                ("Name", "always"),
                ("ExitHandler", CreateAppendScript(markerFile, "A")));
            Invoke(runspace, "Register-ExitHandler",
                ("Name", "onFailure"),
                ("ExitHandler", CreateAppendScript(markerFile, "F")),
                ("OnlyFailure", true));

            Invoke(runspace, "Invoke-Handlers", ("IsFailure", false));

            Assert.That(File.ReadAllLines(markerFile), Is.EqualTo(new[] { "A" }));

            ExitStore.Reset(runspace);
            File.WriteAllText(markerFile, string.Empty);

            Invoke(runspace, "Register-ExitHandler",
                ("Name", "always"),
                ("ExitHandler", CreateAppendScript(markerFile, "A")));
            Invoke(runspace, "Register-ExitHandler",
                ("Name", "onFailure"),
                ("ExitHandler", CreateAppendScript(markerFile, "F")),
                ("OnlyFailure", true));

            Invoke(runspace, "Invoke-Handlers", ("IsFailure", true));

            Assert.That(
                File.ReadAllLines(markerFile).OrderBy(value => value, StringComparer.Ordinal),
                Is.EqualTo(new[] { "A", "F" }));
        } finally {
            TryDeleteFile(markerFile);
        }
    }

    [Test]
    public void InvokeFailedExit_ThrowsWithExitCodeAsTargetObject() {
        using var runspace = CreateRunspace();

        var result = Invoke(runspace, "Invoke-FailedExit", ("ExitCode", 1));

        Assert.Multiple(() => {
            Assert.That(result.ThrownException, Is.Not.Null);
            Assert.That(result.ThrownException!.ErrorRecord, Is.Not.Null);
            Assert.That(result.ThrownException.ErrorRecord.TargetObject, Is.EqualTo(1));
            Assert.That(result.ThrownException.ErrorRecord.FullyQualifiedErrorId, Does.Contain("FailedExit"));
        });
    }

    [Test]
    public void InvokeFailedExit_PropagatesCategoryFromProvidedErrorRecord() {
        using var runspace = CreateRunspace();

        var provided = new ErrorRecord(
            new InvalidOperationException("boom"),
            "Boom",
            ErrorCategory.ResourceUnavailable,
            "provided-target");

        var result = Invoke(runspace, "Invoke-FailedExit", ("ExitCode", 5), ("ErrorRecord", provided));

        Assert.Multiple(() => {
            Assert.That(result.ThrownException, Is.Not.Null);
            Assert.That(
                result.ThrownException!.ErrorRecord.CategoryInfo.Category,
                Is.EqualTo(ErrorCategory.ResourceUnavailable));
            Assert.That(result.ThrownException.ErrorRecord.TargetObject, Is.EqualTo(5));
        });
    }

    [Test]
    public void InvokeFailedExit_EmitsPrefixedErrorDisplayToInformationStream() {
        using var runspace = CreateRunspace();

        Invoke(runspace, "Register-ExitCode", ("Description", "something went wrong"));

        var result = Invoke(runspace, "Invoke-FailedExit", ("ExitCode", 1001), ("DontExit", true));

        Assert.That(result.ThrownException, Is.Null);

        var messages = result.Information.Select(info => info.MessageData?.ToString() ?? string.Empty).ToList();

        Assert.That(messages, Has.Some.Contain("❌ something went wrong"));
    }

    [Test]
    public void InvokeFailedExit_EmitsFallbackMessageForUnregisteredNonZeroExitCode() {
        using var runspace = CreateRunspace();

        var result = Invoke(runspace, "Invoke-FailedExit", ("ExitCode", 5000), ("DontExit", true));

        Assert.That(result.ThrownException, Is.Null);

        var messages = result.Information.Select(info => info.MessageData?.ToString() ?? string.Empty).ToList();

        Assert.That(messages, Has.Some.Contain("❌ Exit code 5000"));
    }

    [Test]
    public void InvokeFailedExit_DontExitDoesNotThrow() {
        using var runspace = CreateRunspace();

        var result = Invoke(runspace, "Invoke-FailedExit", ("ExitCode", 1), ("DontExit", true));

        Assert.That(result.ThrownException, Is.Null);
    }

    [Test]
    public void InvokeQuickExit_ThrowsQuickExitError() {
        using var runspace = CreateRunspace();

        var result = Invoke(runspace, "Invoke-QuickExit");

        Assert.Multiple(() => {
            Assert.That(result.ThrownException, Is.Not.Null);
            Assert.That(result.ThrownException!.ErrorRecord.FullyQualifiedErrorId, Does.Contain("QuickExit"));
        });
    }

    [Test]
    public void RestartScript_ThrowsRestartScriptError() {
        using var runspace = CreateRunspace();

        var result = Invoke(runspace, "Restart-Script");

        Assert.Multiple(() => {
            Assert.That(result.ThrownException, Is.Not.Null);
            Assert.That(result.ThrownException!.ErrorRecord.FullyQualifiedErrorId, Does.Contain("RestartScript"));
        });
    }

    private static Runspace CreateRunspace() {
        var initialSessionState = InitialSessionState.CreateDefault2();
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Register-ExitHandler", typeof(RegisterExitHandlerCommand), null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Register-ExitCode", typeof(RegisterExitCodeCommand), null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Invoke-Handlers", typeof(InvokeHandlersCommand), null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Invoke-FailedExit", typeof(InvokeFailedExitCommand), null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Invoke-QuickExit", typeof(InvokeQuickExitCommand), null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Restart-Script", typeof(RestartScriptCommand), null));

        var runspace = RunspaceFactory.CreateRunspace(initialSessionState);
        runspace.Open();
        return runspace;
    }

    private static ScriptBlock CreateAppendScript(string path, string value) {
        var escaped = path.Replace("'", "''");
        return ScriptBlock.Create($"Add-Content -Path '{escaped}' -Value '{value}'");
    }

    private static InvocationResult Invoke(Runspace runspace, string cmdlet, params (string Name, object? Value)[] parameters) {
        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddCommand(cmdlet);

        foreach (var (name, value) in parameters) {
            powerShell.AddParameter(name, value);
        }

        var output = new Collection<PSObject>();
        RuntimeException? thrown = null;

        try {
            powerShell.Invoke(null, output);
        } catch (RuntimeException exception) {
            thrown = exception;
        }

        return new InvocationResult(
            output,
            [.. powerShell.Streams.Information],
            [.. powerShell.Streams.Error],
            thrown);
    }

    private static void TryDeleteFile(string path) {
        try {
            if (File.Exists(path)) {
                File.Delete(path);
            }
        } catch {
        }
    }

    private sealed record InvocationResult(
        Collection<PSObject> Output,
        IReadOnlyList<InformationRecord> Information,
        IReadOnlyList<ErrorRecord> Errors,
        RuntimeException? ThrownException);
}
