// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text.RegularExpressions;
using AMT.PowerShell.Common.Commands.Logging;
using NUnit.Framework;

namespace AMT.PowerShell.Common.Tests.Commands.Logging;

[TestFixture]
[NonParallelizable]
public sealed class LoggingCommandTests {
    public static List<string> SideEffects { get; } = new();

    private const string SideEffectsTypeName = "AMT.PowerShell.Common.Tests.Commands.Logging.LoggingCommandTests";

    [SetUp]
    public void SetUp() {
        SideEffects.Clear();
        LoggingRuntime.SupportsUnicodeOverride = () => true;
        LoggingRuntime.SupportsColourOverride = () => false;
        LoggingRuntime.ConsoleKeyAvailableOverride = null;
        LoggingRuntime.SleepOverride = null;
    }

    [TearDown]
    public void TearDown() {
        LoggingRuntime.SupportsUnicodeOverride = null;
        LoggingRuntime.SupportsColourOverride = null;
        LoggingRuntime.ConsoleKeyAvailableOverride = null;
        LoggingRuntime.SleepOverride = null;
    }

    [Test]
    public void InvokeWrite_ShouldWriteFalse_WritesNothing() {
        var result = Invoke(
            "Invoke-Write",
            new Dictionary<string, object?> {
                ["PSMessage"] = "Test message",
                ["PSColour"] = "Green",
                ["PSPrefix"] = "\U0001F31F",
                ["ShouldWrite"] = false,
            });

        Assert.That(result.Information, Is.Empty);
    }

    [Test]
    public void InvokeWrite_ShouldWriteTrue_WritesMessage() {
        var result = Invoke(
            "Invoke-Write",
            new Dictionary<string, object?> {
                ["PSMessage"] = "Test message",
                ["PSColour"] = "Green",
                ["PSPrefix"] = "\U0001F31F",
                ["ShouldWrite"] = true,
            });

        Assert.That(result.Information.Select(Strip), Is.EqualTo(new[] { " Test message" }));
    }

    [Test]
    public void InvokeWrite_Multiline_ReplacesNewline() {
        var result = Invoke(
            "Invoke-Write",
            new Dictionary<string, object?> {
                ["PSMessage"] = "Test message\nSecond line",
                ["PSColour"] = "Green",
                ["PSPrefix"] = "\U0001F31F",
                ["ShouldWrite"] = true,
            });

        Assert.That(result.Information.Select(Strip), Is.EqualTo(new[] { " Test message\n  + Second line" }));
    }

    [Test]
    public void InvokeWrite_PassThru_ReturnsFormattedMessage() {
        var result = Invoke(
            "Invoke-Write",
            new Dictionary<string, object?> {
                ["PSMessage"] = "Test message",
                ["PSColour"] = "Green",
                ["PSPrefix"] = "\U0001F31F",
                ["ShouldWrite"] = true,
                ["PassThru"] = SwitchParameter.Present,
            });

        Assert.That(result.Output.Select(static value => value?.ToString()).Select(Strip), Is.EqualTo(new[] { " Test message" }));
    }

    [Test]
    public void InvokeWrite_InputObjectSplat_WritesMessage() {
        var splat = new Hashtable {
            ["PSMessage"] = "Splatted message",
            ["PSColour"] = "Cyan",
            ["PSPrefix"] = "\U0001F31F",
            ["ShouldWrite"] = true,
        };

        var result = Invoke("Invoke-Write", new Dictionary<string, object?> { ["InputObject"] = splat });

        Assert.That(result.Information.Select(Strip), Is.EqualTo(new[] { " Splatted message" }));
    }

    [Test]
    public void InvokeWrite_InformationTag_TagsInformation() {
        var result = Invoke(
            "Invoke-Write",
            new Dictionary<string, object?> {
                ["PSMessage"] = "Tagged message",
                ["PSColour"] = "White",
                ["ShouldWrite"] = true,
                ["InformationTag"] = "AMT.ErrorDisplay",
            });

        Assert.Multiple(() => {
            Assert.That(result.Information.Select(Strip), Is.EqualTo(new[] { "Tagged message" }));
            Assert.That(result.InformationRecords, Has.Count.EqualTo(1));
            Assert.That(result.InformationRecords[0].Tags, Does.Contain("AMT.ErrorDisplay"));
        });
    }

    [Test]
    public void InvokeWrite_Writes_WhenInformationPreferenceSilentlyContinue() {
        var result = Invoke(
            "Invoke-Write",
            new Dictionary<string, object?> {
                ["PSMessage"] = "visible",
                ["PSColour"] = "White",
                ["ShouldWrite"] = true,
            },
            new Dictionary<string, object?> {
                ["InformationPreference"] = ActionPreference.SilentlyContinue,
            });

        Assert.That(result.Information.Select(Strip), Is.EqualTo(new[] { "visible" }));
    }

    [Test]
    public void InvokeWrite_Writes_WhenInformationPreferenceIgnore() {
        var result = Invoke(
            "Invoke-Write",
            new Dictionary<string, object?> {
                ["PSMessage"] = "forced",
                ["PSColour"] = "White",
                ["ShouldWrite"] = true,
            },
            new Dictionary<string, object?> {
                ["InformationPreference"] = ActionPreference.Ignore,
            });

        Assert.That(result.Information.Select(Strip), Is.EqualTo(new[] { "forced" }));
    }

    [Test]
    public void InvokeInfo_Writes_WhenInformationPreferenceSilentlyContinue() {
        var result = Invoke(
            "Invoke-Info",
            new Dictionary<string, object?> { ["Message"] = "visible" },
            new Dictionary<string, object?> {
                ["InformationPreference"] = ActionPreference.SilentlyContinue,
            });

        Assert.That(result.Information.Select(Strip), Is.EqualTo(new[] { " visible" }));
    }

    [Test]
    [TestCase("Verbose", "VerbosePreference", ActionPreference.Continue, true)]
    [TestCase("Verbose", "VerbosePreference", ActionPreference.SilentlyContinue, false)]
    [TestCase("Verbose", "VerbosePreference", ActionPreference.Ignore, false)]
    [TestCase("Debug", "DebugPreference", ActionPreference.Continue, true)]
    [TestCase("Debug", "DebugPreference", ActionPreference.SilentlyContinue, false)]
    [TestCase("Debug", "DebugPreference", ActionPreference.Ignore, false)]
    [TestCase("Warn", "WarningPreference", ActionPreference.Continue, true)]
    [TestCase("Warn", "WarningPreference", ActionPreference.SilentlyContinue, false)]
    [TestCase("Warn", "WarningPreference", ActionPreference.Ignore, false)]
    [TestCase("Info", "InformationPreference", ActionPreference.Continue, true)]
    [TestCase("Info", "InformationPreference", ActionPreference.SilentlyContinue, true)]
    [TestCase("Info", "InformationPreference", ActionPreference.Ignore, false)]
    [TestCase("Error", "ErrorActionPreference", ActionPreference.Continue, true)]
    [TestCase("Error", "ErrorActionPreference", ActionPreference.SilentlyContinue, false)]
    [TestCase("Error", "ErrorActionPreference", ActionPreference.Ignore, false)]
    public void InvokeLevel_GatesOnPreference(string noun, string preferenceName, ActionPreference preference, bool shouldWrite) {
        var result = Invoke(
            $"Invoke-{noun}",
            new Dictionary<string, object?> { ["Message"] = "Test message" },
            new Dictionary<string, object?> { [preferenceName] = preference });

        var stripped = result.Information.Select(Strip).ToList();

        if (shouldWrite) {
            Assert.That(stripped, Has.Count.EqualTo(1));
            Assert.That(stripped[0], Is.EqualTo(" Test message"));
        } else {
            Assert.That(stripped, Is.Empty);
        }
    }

    [Test]
    public void InvokeError_Throw_ThrowsTerminatingError() {
        var exception = Assert.Throws<CmdletInvocationException>(() => Invoke(
            "Invoke-Error",
            new Dictionary<string, object?> {
                ["Message"] = "boom",
                ["Throw"] = SwitchParameter.Present,
                ["ErrorCategory"] = ErrorCategory.InvalidOperation,
            }));

        Assert.Multiple(() => {
            Assert.That(exception, Is.Not.Null);
            Assert.That(exception!.ErrorRecord.CategoryInfo.Category, Is.EqualTo(ErrorCategory.InvalidOperation));
            Assert.That(exception.ErrorRecord.Exception.Message, Is.EqualTo("boom"));
        });
    }

    [Test]
    public void InvokeError_Throw_DefaultsCallerToInvocationInfo() {
        var exception = Assert.Throws<CmdletInvocationException>(() => Invoke(
            "Invoke-Error",
            new Dictionary<string, object?> {
                ["Message"] = "boom",
                ["Throw"] = SwitchParameter.Present,
            }));

        var target = exception!.ErrorRecord.TargetObject;
        if (target is PSObject psObject) {
            target = psObject.BaseObject;
        }

        Assert.That(target, Is.InstanceOf<InvocationInfo>());
    }

    [Test]
    public void InvokeError_Throw_SplatHonorsCaller() {
        var caller = GetInvocationInfo();
        var splat = new Hashtable {
            ["Message"] = "boom",
            ["Throw"] = true,
            ["ErrorCategory"] = ErrorCategory.InvalidOperation,
            ["Caller"] = caller,
        };

        var exception = Assert.Throws<CmdletInvocationException>(() => Invoke(
            "Invoke-Error",
            new Dictionary<string, object?> { ["InputObject"] = splat }));

        var target = exception!.ErrorRecord.TargetObject;
        if (target is PSObject psObject) {
            target = psObject.BaseObject;
        }

        Assert.Multiple(() => {
            Assert.That(target, Is.SameAs(caller));
            Assert.That(exception.ErrorRecord.CategoryInfo.Category, Is.EqualTo(ErrorCategory.InvalidOperation));
        });
    }

    [Test]
    public void InvokeError_NonTerminating_WritesInformation() {
        var result = Invoke(
            "Invoke-Error",
            new Dictionary<string, object?> { ["Message"] = "recoverable" },
            new Dictionary<string, object?> { ["ErrorActionPreference"] = ActionPreference.Continue });

        Assert.Multiple(() => {
            Assert.That(result.Information.Select(Strip), Is.EqualTo(new[] { " recoverable" }));
            Assert.That(result.InformationRecords[0].Tags, Does.Contain("AMT.ErrorDisplay"));
        });
    }

    [Test]
    public void FormatError_ErrorRecord_PassThru_ReturnsRows() {
        var record = new FakeParseError {
            Message = "boom",
            Extent = new FakeExtent {
                File = "file.ps1",
                StartLineNumber = 2,
                EndLineNumber = 2,
                StartColumnNumber = 5,
                EndColumnNumber = 10,
                Text = "Get-Foo",
            },
        };

        var result = Invoke(
            "Format-Error",
            new Dictionary<string, object?> {
                ["ErrorRecord"] = record,
                ["PassThru"] = SwitchParameter.Present,
            });

        var output = string.Join("\n", result.Output.Select(static value => value?.ToString()));

        Assert.Multiple(() => {
            Assert.That(output, Does.Contain("file.ps1"));
            Assert.That(output, Does.Contain("2[5..10]"));
            Assert.That(output, Does.Contain("Get-Foo"));
            Assert.That(output, Does.Contain("boom"));
        });
    }

    [Test]
    public void FormatError_InvocationInfo_PassThru_ReturnsRows() {
        var invocationInfo = GetInvocationInfo();

        var result = Invoke(
            "Format-Error",
            new Dictionary<string, object?> {
                ["InvocationInfo"] = invocationInfo,
                ["Message"] = "boom",
                ["PassThru"] = SwitchParameter.Present,
            });

        var output = string.Join("\n", result.Output.Select(static value => value?.ToString()));

        Assert.Multiple(() => {
            Assert.That(result.Output, Is.Not.Empty);
            Assert.That(output, Does.Contain("boom"));
        });
    }

    [Test]
    public void InvokeTimeout_InvokesTimeoutScript() {
        LoggingRuntime.SleepOverride = static _ => { };

        var result = Invoke(
            "Invoke-Timeout",
            new Dictionary<string, object?> {
                ["Timeout"] = 0,
                ["Activity"] = "test",
                ["StatusMessage"] = "{0}s left",
                ["TimeoutScript"] = ScriptBlock.Create($"[{SideEffectsTypeName}]::SideEffects.Add('timeout')"),
            });

        Assert.Multiple(() => {
            Assert.That(SideEffects, Is.EqualTo(new[] { "timeout" }));
            Assert.That(result.Errors, Is.Empty);
        });
    }

    [Test]
    public void InvokeTimeout_InvokesCancelScript_WhenCancelled() {
        LoggingRuntime.ConsoleKeyAvailableOverride = () => true;

        var result = Invoke(
            "Invoke-Timeout",
            new Dictionary<string, object?> {
                ["Timeout"] = 0,
                ["Activity"] = "test",
                ["StatusMessage"] = "{0}s left",
                ["AllowCancel"] = SwitchParameter.Present,
                ["CancelScript"] = ScriptBlock.Create($"[{SideEffectsTypeName}]::SideEffects.Add('cancelled')"),
            });

        Assert.Multiple(() => {
            Assert.That(SideEffects, Is.EqualTo(new[] { "cancelled" }));
            Assert.That(result.Errors, Is.Empty);
        });
    }

    [Test]
    public void InvokeProgress_ProcessesEachItem() {
        var result = Invoke(
            "Invoke-Progress",
            new Dictionary<string, object?> {
                ["Activity"] = "test",
                ["Get"] = ScriptBlock.Create("1, 2, 3"),
                ["Process"] = ScriptBlock.Create($"[{SideEffectsTypeName}]::SideEffects.Add($args[0].ToString())"),
            });

        Assert.Multiple(() => {
            Assert.That(SideEffects, Is.EqualTo(new[] { "1", "2", "3" }));
            Assert.That(result.Errors, Is.Empty);
            Assert.That(result.Progress, Has.Count.GreaterThanOrEqualTo(1));
        });
    }

    [Test]
    public void InvokeProgress_EmptyCollection_WritesNoItemsFound() {
        var result = Invoke(
            "Invoke-Progress",
            new Dictionary<string, object?> {
                ["Activity"] = "test",
                ["Get"] = ScriptBlock.Create("$null"),
                ["Process"] = ScriptBlock.Create($"[{SideEffectsTypeName}]::SideEffects.Add($args[0].ToString())"),
            });

        Assert.Multiple(() => {
            Assert.That(SideEffects, Is.Empty);
            Assert.That(result.Progress.Any(static progress => progress.StatusDescription == "No items found."), Is.True);
        });
    }

    [Test]
    public void InvokeProgress_FailedItem_InvokesFailedProcessItem() {
        var result = Invoke(
            "Invoke-Progress",
            new Dictionary<string, object?> {
                ["Activity"] = "test",
                ["Get"] = ScriptBlock.Create("1, 2"),
                ["Process"] = ScriptBlock.Create($"[{SideEffectsTypeName}]::SideEffects.Add($args[0].ToString()); if ($args[0] -eq 1) {{ throw 'fail' }}"),
                ["FailedProcessItem"] = ScriptBlock.Create($"[{SideEffectsTypeName}]::SideEffects.Add('failed:' + $args[0].ToString())"),
            });

        Assert.Multiple(() => {
            Assert.That(SideEffects, Is.EqualTo(new[] { "1", "failed:1", "2" }));
            Assert.That(result.Warnings, Does.Contain("Failed to process item [1]"));
            Assert.That(result.Errors, Is.Empty);
        });
    }

    [Test]
    public void InvokeProgress_NonTerminatingProcessError_IsTerminating() {
        var result = Invoke(
            "Invoke-Progress",
            new Dictionary<string, object?> {
                ["Activity"] = "test",
                ["Get"] = ScriptBlock.Create("1"),
                ["Process"] = ScriptBlock.Create("Write-Error 'boom'"),
                ["FailedProcessItem"] = ScriptBlock.Create($"[{SideEffectsTypeName}]::SideEffects.Add('failed:' + $args[0].ToString())"),
            });

        Assert.Multiple(() => {
            Assert.That(SideEffects, Is.EqualTo(new[] { "failed:1" }));
            Assert.That(result.Warnings, Does.Contain("Failed to process item [1]"));
        });
    }

    [Test]
    public void InvokeProgress_NonTerminatingFailedProcessItemError_IsTerminating() {
        var result = Invoke(
            "Invoke-Progress",
            new Dictionary<string, object?> {
                ["Activity"] = "test",
                ["Get"] = ScriptBlock.Create("1"),
                ["Process"] = ScriptBlock.Create("throw 'fail'"),
                ["FailedProcessItem"] = ScriptBlock.Create("Write-Error 'also fails'"),
            });

        Assert.Multiple(() => {
            Assert.That(result.Warnings, Does.Contain("Failed to process item [1]"));
            Assert.That(result.Warnings, Does.Contain("Failed to process item [1] in failed process item block"));
        });
    }

    private static InvocationInfo GetInvocationInfo() {
        using var runspace = RunspaceFactory.CreateRunspace(InitialSessionState.CreateDefault2());
        runspace.Open();

        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddScript("$MyInvocation");

        var result = powerShell.Invoke();
        return (InvocationInfo)result[0].BaseObject;
    }

    private static InvocationResult Invoke(
        string commandName,
        IDictionary<string, object?>? parameters = null,
        IDictionary<string, object?>? variables = null) {
        var initialSessionState = InitialSessionState.CreateDefault2();
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Invoke-Write", typeof(InvokeWriteCommand), helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Invoke-Verbose", typeof(InvokeVerboseCommand), helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Invoke-Debug", typeof(InvokeDebugCommand), helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Invoke-Info", typeof(InvokeInfoCommand), helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Invoke-Warn", typeof(InvokeWarnCommand), helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Invoke-Error", typeof(InvokeErrorCommand), helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Format-Error", typeof(FormatErrorCommand), helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Invoke-Timeout", typeof(InvokeTimeoutCommand), helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Invoke-Progress", typeof(InvokeProgressCommand), helpFileName: null));

        using var runspace = RunspaceFactory.CreateRunspace(initialSessionState);
        runspace.Open();

        if (variables is not null) {
            foreach (var (name, value) in variables) {
                runspace.SessionStateProxy.SetVariable(name, value);
            }
        }

        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddCommand(commandName);

        if (parameters is not null) {
            foreach (var (name, value) in parameters) {
                powerShell.AddParameter(name, value);
            }
        }

        var output = powerShell.Invoke();
        var information = powerShell.Streams.Information.ToList();
        var warnings = powerShell.Streams.Warning.Select(static warning => warning.Message).ToList();
        var errors = powerShell.Streams.Error.ToList();
        var progress = powerShell.Streams.Progress.ToList();

        return new InvocationResult(
            output.Select(static value => value?.BaseObject).ToList(),
            information.Select(static record => record.MessageData?.ToString() ?? string.Empty).ToList(),
            information,
            warnings,
            errors,
            progress);
    }

    private static string Strip(string value) {
        var withoutAnsi = Regex.Replace(value, "\u001b\\[[0-9;]*m", string.Empty);
        return new string(withoutAnsi.Where(static character => character <= 0x7F).ToArray());
    }

    private sealed record InvocationResult(
        IReadOnlyList<object?> Output,
        IReadOnlyList<string> Information,
        IReadOnlyList<InformationRecord> InformationRecords,
        IReadOnlyList<string> Warnings,
        IReadOnlyList<ErrorRecord> Errors,
        IReadOnlyList<ProgressRecord> Progress);

    private sealed class FakeExtent {
        public string File { get; init; } = string.Empty;

        public int StartLineNumber { get; init; }

        public int EndLineNumber { get; init; }

        public int StartColumnNumber { get; init; }

        public int EndColumnNumber { get; init; }

        public string Text { get; init; } = string.Empty;
    }

    private sealed class FakeParseError {
        public string Message { get; init; } = string.Empty;

        public FakeExtent Extent { get; init; } = new();
    }
}
