// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Security;
using System.Text.RegularExpressions;
using AMT.PowerShell.Common.Commands.Input;

namespace AMT.PowerShell.Common.Tests.Commands.Input;

[TestFixture]
[NonParallelizable]
public sealed class InputCommandTests {
    [TearDown]
    public void TearDown() {
        InputOperations.ReadInputOverride = null;
        InputOperations.ReadSelectionOverride = null;
        InputOperations.PopupSelectionOverride = null;
        InputOperations.ForcePopupFallback = false;
    }

    [Test]
    public void GetUserInput_ValidationLoop_RetriesUntilValidInput() {
        var responses = new Queue<string?>(new[] { "invalid", "valid" });
        InputOperations.ReadInputOverride = (_, _, _, _) => responses.Dequeue();

        var result = InvokeSingle(
            "Get-UserInput",
            ("Title", "Input"),
            ("Prompt", "Enter value"),
            ("Validate", ScriptBlock.Create("param($Value) $Value -eq 'valid'")));

        Assert.Multiple(() => {
            Assert.That(result.BaseObject, Is.EqualTo("valid"));
            Assert.That(responses, Is.Empty);
        });
    }

    [Test]
    public void GetUserInput_AsSecureString_AndAllowEmpty_ReturnsNullForEmptyInput() {
        InputOperations.ReadInputOverride = (_, _, _, _) => string.Empty;

        var result = Invoke(
            "Get-UserInput",
            ("Title", "Input"),
            ("Question", "Enter value"),
            ("AsSecureString", true),
            ("AllowEmpty", true));

        Assert.That(result.Errors, Is.Empty);
        Assert.That(IsNullResult(result.Output), Is.True);
    }

    [Test]
    public void GetUserInput_AsSecureString_ReturnsSecureStringForNonEmptyInput() {
        InputOperations.ReadInputOverride = (_, _, _, _) => "top-secret";

        var result = InvokeSingle(
            "Get-UserInput",
            ("Title", "Input"),
            ("Question", "Enter value"),
            ("AsSecureString", true));

        Assert.That(result.BaseObject, Is.TypeOf<SecureString>());
    }

    [Test]
    public void GetUserSelection_DefaultChoice_UsesDefaultWhenInputIsEmpty() {
        var responses = new Queue<InputSelectionResult>(new[] { new InputSelectionResult(false, string.Empty) });
        InputOperations.ReadSelectionOverride = (_, _, _, _, _) => responses.Dequeue();

        var result = InvokeSingle(
            "Get-UserSelection",
            ("Title", "Select"),
            ("Question", "Choose one"),
            ("Choices", new object[] { "One", "Two" }),
            ("DefaultChoice", 1));

        Assert.That(result.BaseObject, Is.EqualTo("Two"));
    }

    [Test]
    public void GetUserSelection_OmittedDefaultChoice_DoesNotAutoSelectFirstChoice() {
        var responses = new Queue<InputSelectionResult>(new[] {
            new InputSelectionResult(false, string.Empty),
            new InputSelectionResult(false, "Two"),
        });

        InputOperations.ReadSelectionOverride = (_, _, _, _, _) => responses.Dequeue();

        var result = InvokeSingle(
            "Get-UserSelection",
            ("Title", "Select"),
            ("Question", "Choose one"),
            ("Choices", new object[] { "One", "Two" }));

        Assert.Multiple(() => {
            Assert.That(result.BaseObject, Is.EqualTo("Two"));
            Assert.That(responses, Is.Empty);
        });
    }

    [Test]
    public void GetUserSelection_InvalidThenFormattedValue_ReturnsMatchingOriginalChoice() {
        var responses = new Queue<InputSelectionResult>(new[] {
            new InputSelectionResult(false, "bad"),
            new InputSelectionResult(false, "Option-2"),
        });

        InputOperations.ReadSelectionOverride = (_, _, _, _, _) => responses.Dequeue();

        var result = InvokeSingle(
            "Get-UserSelection",
            ("Title", "Select"),
            ("Question", "Choose one"),
            ("Choices", new object[] { 1, 2 }),
            ("FormatChoice", ScriptBlock.Create("param($Choice) \"Option-$Choice\"")));

        Assert.Multiple(() => {
            Assert.That(result.BaseObject, Is.EqualTo(2));
            Assert.That(responses, Is.Empty);
        });
    }

    [Test]
    public void GetUserSelection_AllowNone_ReturnsNullWhenSelectionIsCanceled() {
        InputOperations.ReadSelectionOverride = (_, _, _, _, _) => new InputSelectionResult(true, null);

        var result = Invoke(
            "Get-UserSelection",
            ("Title", "Select"),
            ("Question", "Choose one"),
            ("Choices", new object[] { "One", "Two" }),
            ("AllowNone", true));

        Assert.That(result.Errors, Is.Empty);
        Assert.That(IsNullResult(result.Output), Is.True);
    }

    [TestCase(true, true)]
    [TestCase(false, false)]
    [TestCase(null, false)]
    public void GetUserConfirmation_DefaultChoice_MapsToBool(bool? defaultChoice, bool expected) {
        InputOperations.ReadSelectionOverride = (_, _, _, _, _) => new InputSelectionResult(false, string.Empty);

        var parameters = new List<(string Name, object? Value)> {
            ("Title", "Confirm"),
            ("Question", "Continue?"),
        };

        if (defaultChoice.HasValue) {
            parameters.Add(("DefaultChoice", defaultChoice.Value));
        }

        var result = InvokeSingle("Get-UserConfirmation", [.. parameters]);

        Assert.That(result.BaseObject, Is.EqualTo(expected));
    }

    [Test]
    public void GetPopupSelection_FallbackPath_ReturnsStableSelectionWithoutGui() {
        InputOperations.ForcePopupFallback = true;

        var result = InvokeSingle(
            "Get-PopupSelection",
            ("Title", "Popup"),
            ("Items", new object[] { "One", "Two" }));

        Assert.That(result.BaseObject, Is.EqualTo("One"));
    }

    [Test]
    public void ModuleImport_ExposesValidationsVariable_ForScriptConsumers() {
        var moduleSourceDirectory = Path.GetFullPath(Path.Combine(TestContext.CurrentContext.TestDirectory, "..", "..", "..", "..", "..", "src", "AMT.PowerShell.Common", "Module"));
        var moduleDirectory = Path.Combine(Path.GetTempPath(), $"amt-input-module-{Guid.NewGuid():N}");
        Directory.CreateDirectory(moduleDirectory);

        try {
            File.Copy(Path.Combine(moduleSourceDirectory, "AMT.PowerShell.Common.psd1"), Path.Combine(moduleDirectory, "AMT.PowerShell.Common.psd1"), overwrite: true);
            File.Copy(typeof(GetUserInputCommand).Assembly.Location, Path.Combine(moduleDirectory, "AMT.PowerShell.Common.dll"), overwrite: true);

            using var runspace = RunspaceFactory.CreateRunspace(InitialSessionState.CreateDefault2());
            runspace.Open();

            using var powerShell = System.Management.Automation.PowerShell.Create();
            powerShell.Runspace = runspace;

            var manifestPath = Path.Combine(moduleDirectory, "AMT.PowerShell.Common.psd1").Replace("'", "''");
            var importScript = "function Invoke-LocalImport {\n"
                + $"    Import-Module -Name '{manifestPath}' -Force | Out-Null\n"
                + "}\n\n"
                + "Invoke-LocalImport\n"
                + "[pscustomobject]@{\n"
                + "    Validations = $Validations\n"
                + "    HasVariable = [bool](Get-Variable -Name 'Validations' -ErrorAction SilentlyContinue)\n"
                + "}\n";
            powerShell.AddScript(importScript);

            var output = powerShell.Invoke();

            Assert.That(powerShell.HadErrors, Is.False, $"Import script failed: {FormatErrors(powerShell.Streams.Error)}");
            Assert.That(output, Has.Count.EqualTo(1));

            var payload = output[0];
            var table = payload.Properties["Validations"].Value as Hashtable;
            var hasVariable = payload.Properties["HasVariable"].Value is true;
            Assert.That(table, Is.Not.Null);
            Assert.That(hasVariable, Is.True);

            var emailRegex = table!["Email"]?.ToString();
            Assert.That(emailRegex, Is.Not.Null.And.Not.Empty);
        } finally {
            TryDeleteDirectory(moduleDirectory);
        }
    }

    [Test]
    public void Validations_VariableIsAvailable_AndEmailRegexIsCorrect() {
        InputOperations.ReadInputOverride = (_, _, _, _) => "test@mail.testing.com.au";

        using var runspace = CreateRunspace();

        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddScript("""
            $result = Get-UserInput -Title 'Input' -Question 'Enter email' -Validate { param($UserInput) $UserInput -match $Validations.Email }
            [pscustomobject]@{
                Result = $result
                Validations = $Validations
            }
            """);

        var output = powerShell.Invoke();

        Assert.That(powerShell.HadErrors, Is.False, $"Validation script failed: {FormatErrors(powerShell.Streams.Error)}");
        Assert.That(output, Has.Count.EqualTo(1));

        var payload = output[0];
        var resultValue = payload.Properties["Result"].Value?.ToString();
        var table = payload.Properties["Validations"].Value as Hashtable;

        Assert.That(resultValue, Is.EqualTo("test@mail.testing.com.au"));
        Assert.That(table, Is.Not.Null);

        var emailRegex = table!["Email"]?.ToString();
        Assert.That(emailRegex, Is.Not.Null.And.Not.Empty);

        Assert.Multiple(() => {
            Assert.That(Regex.IsMatch("test@mail.testing.com.au", emailRegex!), Is.True);
            Assert.That(Regex.IsMatch("test.user@testing.com", emailRegex!), Is.True);
            Assert.That(Regex.IsMatch("invalid-email", emailRegex!), Is.False);
            Assert.That(Regex.IsMatch("test@testing", emailRegex!), Is.False);
        });
    }

    private static PSObject InvokeSingle(string commandName, params (string Name, object? Value)[] parameters) {
        var result = Invoke(commandName, parameters);

        if (result.Errors.Count > 0) {
            throw new AssertionException($"Command '{commandName}' failed:{Environment.NewLine}{FormatErrors(result.Errors)}");
        }

        Assert.That(result.Output, Has.Count.EqualTo(1));
        return result.Output[0];
    }

    private static InvocationResult Invoke(string commandName, params (string Name, object? Value)[] parameters) {
        using var runspace = CreateRunspace();

        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddCommand(commandName);

        foreach (var (name, value) in parameters) {
            powerShell.AddParameter(name, value);
        }

        var output = powerShell.Invoke();
        return new InvocationResult(output, [.. powerShell.Streams.Error]);
    }

    private static Runspace CreateRunspace() {
        var initialSessionState = InitialSessionState.CreateDefault2();
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Get-UserInput", typeof(GetUserInputCommand), helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Get-UserSelection", typeof(GetUserSelectionCommand), helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Get-UserConfirmation", typeof(GetUserConfirmationCommand), helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Get-PopupSelection", typeof(GetPopupSelectionCommand), helpFileName: null));

        var runspace = RunspaceFactory.CreateRunspace(initialSessionState);
        runspace.Open();
        return runspace;
    }

    private static string FormatErrors(IEnumerable<ErrorRecord> errors) =>
        string.Join(Environment.NewLine, errors.Select(static error => error.ToString()));

    private static void TryDeleteDirectory(string path) {
        try {
            if (Directory.Exists(path)) {
                Directory.Delete(path, recursive: true);
            }
        } catch {
        }
    }

    private static bool IsNullResult(IReadOnlyList<PSObject> output) {
        if (output.Count == 0) {
            return true;
        }

        return output.Count == 1 && output[0] is null;
    }

    private sealed record InvocationResult(
        Collection<PSObject> Output,
        IReadOnlyList<ErrorRecord> Errors);
}
