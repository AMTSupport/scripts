// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using AMT.PowerShell.Common.Commands.EnvironmentCmdlets;
using AMT.PowerShell.Common.Commands.Exit;

namespace AMT.PowerShell.Common.Tests.Commands.EnvironmentCmdlets;

[TestFixture]
[NonParallelizable]
public sealed class EnvironmentCommandTests {
    [Test]
    public void InvokeRunMain_SuccessPath_InvokesMainAndReportsFinished() {
        using var runspace = CreateRunspace();

        var result = InvokeRunMain(runspace, main: ScriptBlock.Create("'hello-from-main'"));

        Assert.Multiple(() => {
            Assert.That(result.ThrownException, Is.Null);
            Assert.That(result.Output.Select(o => o.ToString()), Does.Contain("hello-from-main"));
            Assert.That(
                result.Information.Select(i => i.MessageData?.ToString() ?? string.Empty),
                Does.Contain("Main function finished successfully."));
        });
    }

    [Test]
    public void InvokeRunMain_RunsExitHandlersOnSuccess() {
        using var runspace = CreateRunspace();
        ExitStore.RegisterHandler(runspace, "success", ScriptBlock.Create("$Global:__successHandlerRan = $true"), onlyFailure: false);

        var result = InvokeRunMain(runspace, main: ScriptBlock.Create("'ok'"));

        Assert.Multiple(() => {
            Assert.That(result.ThrownException, Is.Null);
            Assert.That(runspace.SessionStateProxy.GetVariable("__successHandlerRan"), Is.True);
        });
    }

    [Test]
    public void InvokeRunMain_RunsFailureHandlersOnUncaughtError() {
        using var runspace = CreateRunspace();
        ExitStore.RegisterHandler(runspace, "failure", ScriptBlock.Create("$Global:__failureHandlerRan = $true"), onlyFailure: true);

        var result = InvokeRunMain(runspace, main: ScriptBlock.Create("throw 'boom'"));

        Assert.Multiple(() => {
            Assert.That(result.Errors, Is.Not.Empty);
            Assert.That(runspace.SessionStateProxy.GetVariable("__failureHandlerRan"), Is.True);
            Assert.That(runspace.SessionStateProxy.GetVariable("LASTEXITCODE"), Is.EqualTo(9999));
        });
    }

    [Test]
    public void InvokeRunMain_QuickExit_IsSuccessPath() {
        using var runspace = CreateRunspace();

        var result = InvokeRunMain(runspace, main: ScriptBlock.Create("Invoke-QuickExit"));

        Assert.Multiple(() => {
            Assert.That(result.ThrownException, Is.Null);
            Assert.That(result.Errors, Is.Empty);
            Assert.That(result.Output, Is.Empty);
        });
    }

    [Test]
    public void InvokeRunMain_FailedExit_SetsLastExitCodeFromTargetObject() {
        using var runspace = CreateRunspace();

        var result = InvokeRunMain(runspace, main: ScriptBlock.Create("Invoke-FailedExit -ExitCode 42"));

        Assert.Multiple(() => {
            Assert.That(result.ThrownException, Is.Null);
            Assert.That(runspace.SessionStateProxy.GetVariable("LASTEXITCODE"), Is.EqualTo(42));
        });
    }

    [Test]
    public void InvokeRunMain_RestartScript_RerunsMainOnce() {
        using var runspace = CreateRunspace();
        runspace.SessionStateProxy.SetVariable("__amtRestartCount", 0);

        var result = InvokeRunMain(
            runspace,
            main: ScriptBlock.Create(
                "$Global:__amtRestartCount++; "
                + "if ($Global:__amtRestartCount -lt 2) { Restart-Script } else { 'restarted' }"));

        Assert.Multiple(() => {
            Assert.That(result.ThrownException, Is.Null);
            Assert.That(result.Output.Select(o => o.ToString()), Does.Contain("restarted"));
            Assert.That(runspace.SessionStateProxy.GetVariable("__amtRestartCount"), Is.EqualTo(2));
            Assert.That(EnvironmentStore.IsRestarting(runspace), Is.False);
        });
    }

    [Test]
    public void InvokeRunMain_UncaughtError_SetsExitCode9999() {
        using var runspace = CreateRunspace();

        var result = InvokeRunMain(runspace, main: ScriptBlock.Create("throw 'boom'"));

        Assert.Multiple(() => {
            Assert.That(result.ThrownException, Is.Null);
            Assert.That(result.Errors, Is.Not.Empty);
            Assert.That(runspace.SessionStateProxy.GetVariable("LASTEXITCODE"), Is.EqualTo(9999));
        });
    }


    [Test]
    public void InvokeRunMain_ForwardsCallerBoundParametersToMain() {
        using var runspace = CreateRunspace();

        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddScript(@"
            [CmdletBinding()]
            param($Value)
            Invoke-RunMain -Cmdlet $PSCmdlet -Main { param($Value) 'forwarded:' + $Value }
        ");
        powerShell.AddParameter("Value", 42);

        var result = InvokePowerShell(powerShell);

        Assert.Multiple(() => {
            Assert.That(result.ThrownException, Is.Null);
            Assert.That(result.Output.Select(o => o.ToString()), Does.Contain("forwarded:42"));
        });
    }


    [Test]
    public void InvokeRunMain_ShowsDisclaimerUnlessHidden() {
        using var runspace = CreateRunspace();
        var shown = 0;
        EnvironmentRuntime.DisclaimerOverride = _ => shown++;

        try {
            InvokeRunMain(runspace, main: ScriptBlock.Create("{}"));
            Assert.That(shown, Is.EqualTo(1));

            shown = 0;
            InvokeRunMain(runspace, main: ScriptBlock.Create("{}"), hideDisclaimer: true);
            Assert.That(shown, Is.Zero);
        } finally {
            EnvironmentRuntime.DisclaimerOverride = null;
        }
    }

    [Test]
    public void InvokeRunMain_AppliesStrictModeUnlessNotStrict() {
        using var runspace = CreateRunspace();
        var applied = 0;
        EnvironmentRuntime.SetStrictModeOverride = _ => applied++;

        try {
            InvokeRunMain(runspace, main: ScriptBlock.Create("{}"));
            Assert.That(applied, Is.EqualTo(1));

            applied = 0;
            InvokeRunMain(runspace, main: ScriptBlock.Create("{}"), notStrict: true);
            Assert.That(applied, Is.Zero);
        } finally {
            EnvironmentRuntime.SetStrictModeOverride = null;
        }
    }

    [Test]
    public void InvokeRunMain_EnforcesStrictModeInMainScope() {
        using var runspace = CreateRunspace();

        var result = InvokeRunMain(runspace, main: ScriptBlock.Create("$DefinitelyUndefinedVariableXYZ"));

        Assert.That(result.Errors, Is.Not.Empty);
    }

    [Test]
    public void InvokeRunMain_NotStrictAllowsUndefinedVariable() {
        using var runspace = CreateRunspace();

        var result = InvokeRunMain(
            runspace,
            main: ScriptBlock.Create("$DefinitelyUndefinedVariableXYZ"),
            notStrict: true);

        Assert.That(result.Errors, Is.Empty);
    }

    [Test]
    public void TestIsNableRunner_ReturnsTrueForFmPluginTitle() {
        using var runspace = CreateRunspace();
        EnvironmentRuntime.WindowTitleOverride = _ => @"C:\Windows\System32\fmplugin.exe";

        try {
            var result = Invoke(runspace, "Test-IsNableRunner");
            Assert.That((bool)result.Output.Single().BaseObject, Is.True);
        } finally {
            EnvironmentRuntime.WindowTitleOverride = null;
        }
    }

    [Test]
    public void TestIsNableRunner_ReturnsFalseForOtherTitle() {
        using var runspace = CreateRunspace();
        EnvironmentRuntime.WindowTitleOverride = _ => "powershell.exe";

        try {
            var result = Invoke(runspace, "Test-IsNableRunner");
            Assert.That((bool)result.Output.Single().BaseObject, Is.False);
        } finally {
            EnvironmentRuntime.WindowTitleOverride = null;
        }
    }

    [Test]
    public void TestIsNableRunner_ReturnsFalseWhenTitleMissing() {
        using var runspace = CreateRunspace();
        EnvironmentRuntime.WindowTitleOverride = _ => null;

        try {
            var result = Invoke(runspace, "Test-IsNableRunner");
            Assert.That((bool)result.Output.Single().BaseObject, Is.False);
        } finally {
            EnvironmentRuntime.WindowTitleOverride = null;
        }
    }

    private static Runspace CreateRunspace() {
        var initialSessionState = InitialSessionState.CreateDefault2();
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Invoke-RunMain", typeof(InvokeRunMainCommand), null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Test-IsNableRunner", typeof(TestIsNableRunnerCommand), null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Invoke-QuickExit", typeof(InvokeQuickExitCommand), null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Invoke-FailedExit", typeof(InvokeFailedExitCommand), null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Restart-Script", typeof(RestartScriptCommand), null));

        var runspace = RunspaceFactory.CreateRunspace(initialSessionState);
        runspace.Open();
        return runspace;
    }

    private static InvocationResult InvokeRunMain(
        Runspace runspace,
        ScriptBlock? main = null,
        bool notStrict = false,
        bool hideDisclaimer = false) {
        runspace.SessionStateProxy.SetVariable("__amtMain", main ?? ScriptBlock.Create("{}"));

        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;

        var script =
            "[CmdletBinding()]\n" +
            "param()\n" +
            "Invoke-RunMain -Cmdlet $PSCmdlet -Main $__amtMain" +
            (notStrict ? " -NotStrict" : string.Empty) +
            (hideDisclaimer ? " -HideDisclaimer" : string.Empty) +
            "\n";

        powerShell.AddScript(script);

        return InvokePowerShell(powerShell);
    }

    private static InvocationResult Invoke(Runspace runspace, string cmdlet, params (string Name, object? Value)[] parameters) {
        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddCommand(cmdlet);

        foreach (var (name, value) in parameters) {
            powerShell.AddParameter(name, value);
        }

        return InvokePowerShell(powerShell);
    }

    private static InvocationResult InvokePowerShell(System.Management.Automation.PowerShell powerShell) {
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

    private sealed record InvocationResult(
        Collection<PSObject> Output,
        System.Collections.Generic.IReadOnlyList<InformationRecord> Information,
        System.Collections.Generic.IReadOnlyList<ErrorRecord> Errors,
        RuntimeException? ThrownException);
}
