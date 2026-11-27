// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using AMT.PowerShell.Common.Commands.Temp;

namespace AMT.PowerShell.Common.Tests.Commands.Temp;

[TestFixture]
[NonParallelizable]
public sealed class TempCommandTests {
    [Test]
    public void GetNamedTempFolder_CreatesFolderUnderSystemTemp() {
        var folderName = $"amt-temp-{Guid.NewGuid():N}";
        var expectedPath = Path.Combine(Path.GetTempPath(), folderName);

        try {
            var result = InvokeTempCommand("Get-NamedTempFolder", powerShell => {
                powerShell.AddParameter("Name", folderName);
            });

            Assert.That(result.ThrownException, Is.Null);
            Assert.That(result.Errors, Is.Empty);
            Assert.That(result.Output, Has.Count.EqualTo(1));

            var actualPath = result.Output[0].BaseObject as string;
            Assert.That(actualPath, Is.Not.Null.Or.Empty);

            Assert.Multiple(() => {
                Assert.That(actualPath!, Is.EqualTo(expectedPath));
                Assert.That(Directory.Exists(actualPath), Is.True);
            });
        } finally {
            TryDeleteDirectory(expectedPath);
        }
    }

    [Test]
    public void GetNamedTempFolder_ForceEmpty_RemovesExistingContent() {
        var folderName = $"amt-temp-{Guid.NewGuid():N}";
        var expectedPath = Path.Combine(Path.GetTempPath(), folderName);
        Directory.CreateDirectory(expectedPath);

        var staleFile = Path.Combine(expectedPath, "stale.txt");
        File.WriteAllText(staleFile, "stale-content");

        try {
            var result = InvokeTempCommand("Get-NamedTempFolder", powerShell => {
                powerShell.AddParameter("Name", folderName);
                powerShell.AddParameter("ForceEmpty", true);
            });

            Assert.That(result.ThrownException, Is.Null);
            Assert.That(result.Errors, Is.Empty);
            Assert.That(result.Output, Has.Count.EqualTo(1));

            var actualPath = result.Output[0].BaseObject as string;
            Assert.That(actualPath, Is.EqualTo(expectedPath));

            Assert.Multiple(() => {
                Assert.That(Directory.Exists(expectedPath), Is.True);
                Assert.That(File.Exists(staleFile), Is.False);
            });
        } finally {
            TryDeleteDirectory(expectedPath);
        }
    }

    [Test]
    public void GetUniqueTempFolder_ReturnsUniqueExistingFolders() {
        string? first = null;
        string? second = null;

        try {
            var firstResult = InvokeTempCommand("Get-UniqueTempFolder", _ => { });
            var secondResult = InvokeTempCommand("Get-UniqueTempFolder", _ => { });

            Assert.That(firstResult.ThrownException, Is.Null);
            Assert.That(secondResult.ThrownException, Is.Null);
            Assert.That(firstResult.Errors, Is.Empty);
            Assert.That(secondResult.Errors, Is.Empty);

            first = firstResult.Output[0].BaseObject as string;
            second = secondResult.Output[0].BaseObject as string;

            Assert.Multiple(() => {
                Assert.That(first, Is.Not.Null.Or.Empty);
                Assert.That(second, Is.Not.Null.Or.Empty);
                Assert.That(first, Is.Not.EqualTo(second));
                Assert.That(Directory.Exists(first!), Is.True);
                Assert.That(Directory.Exists(second!), Is.True);
            });
        } finally {
            if (!string.IsNullOrWhiteSpace(first)) {
                TryDeleteDirectory(first!);
            }

            if (!string.IsNullOrWhiteSpace(second)) {
                TryDeleteDirectory(second!);
            }
        }
    }

    [Test]
    public void InvokeWithinEphemeral_CleansFolderAfterSuccess() {
        var result = InvokeTempCommand("Invoke-WithinEphemeral", powerShell => {
            powerShell.AddParameter("ScriptBlock", ScriptBlock.Create("(Get-Location).Path"));
        });

        Assert.That(result.ThrownException, Is.Null);
        Assert.That(result.Errors, Is.Empty);
        Assert.That(result.Output, Has.Count.EqualTo(1));

        var ephemeralPath = result.Output[0].BaseObject as string;
        Assert.That(ephemeralPath, Is.Not.Null.Or.Empty);

        Assert.Multiple(() => {
            Assert.That(ephemeralPath!, Does.StartWith(Path.GetTempPath()));
            Assert.That(Directory.Exists(ephemeralPath), Is.False);
        });
    }

    [Test]
    public void InvokeWithinEphemeral_CleansFolderAfterFailure() {
        var markerFile = Path.Combine(Path.GetTempPath(), $"amt-ephemeral-marker-{Guid.NewGuid():N}.txt");

        try {
            var result = InvokeTempCommand("Invoke-WithinEphemeral", powerShell => {
                powerShell.AddParameter(
                    "ScriptBlock",
                    ScriptBlock.Create($"$path = (Get-Location).Path; Set-Content -Path '{markerFile}' -Value $path; throw 'intentional-temp-failure'"));
            });

            Assert.That(result.ThrownException, Is.Not.Null);
            Assert.That(result.ThrownException!.Message, Does.Contain("intentional-temp-failure"));
            Assert.That(File.Exists(markerFile), Is.True);

            var ephemeralPath = File.ReadAllText(markerFile).Trim();
            Assert.That(ephemeralPath, Is.Not.Empty);
            Assert.That(Directory.Exists(ephemeralPath), Is.False);
        } finally {
            TryDeleteFile(markerFile);
        }
    }

    private static CommandInvocationResult InvokeTempCommand(string commandName, Action<System.Management.Automation.PowerShell> configureCommand) {
        var initialSessionState = InitialSessionState.CreateDefault2();
        initialSessionState.Commands.Add(new SessionStateCmdletEntry(
            "Get-NamedTempFolder",
            typeof(GetNamedTempFolderCommand),
            helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry(
            "Get-UniqueTempFolder",
            typeof(GetUniqueTempFolderCommand),
            helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry(
            "Invoke-WithinEphemeral",
            typeof(InvokeWithinEphemeralCommand),
            helpFileName: null));

        using var runspace = RunspaceFactory.CreateRunspace(initialSessionState);
        runspace.Open();

        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddCommand(commandName);
        configureCommand(powerShell);

        var output = new Collection<PSObject>();
        RuntimeException? thrownException = null;

        try {
            powerShell.Invoke(input: null, output);
        } catch (RuntimeException exception) {
            thrownException = exception;
        }

        return new CommandInvocationResult(output, [.. powerShell.Streams.Error], thrownException);
    }

    private static void TryDeleteDirectory(string path) {
        try {
            if (Directory.Exists(path)) {
                Directory.Delete(path, recursive: true);
            }
        } catch {
        }
    }

    private static void TryDeleteFile(string path) {
        try {
            if (File.Exists(path)) {
                File.Delete(path);
            }
        } catch {
        }
    }

    private sealed record CommandInvocationResult(
        Collection<PSObject> Output,
        IReadOnlyList<ErrorRecord> Errors,
        RuntimeException? ThrownException);
}
