// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using AMT.PowerShell.Common.Commands.Lock;

namespace AMT.PowerShell.Common.Tests.Commands.Lock;

[TestFixture]
[NonParallelizable]
public sealed class LockCommandTests {
    [Test]
    public void GetLockPath_SanitizesScriptAndResourceNames() {
        var result = InvokeLockCommand("Get-LockPath", powerShell => {
            powerShell.AddParameter("ScriptName", "Setup-Printer");
            powerShell.AddParameter("ResourceId", "H.P. (Test)!@#");
        });

        Assert.Multiple(() => {
            Assert.That(result.ThrownException, Is.Null);
            Assert.That(result.Errors, Is.Empty);
            Assert.That(result.Output, Has.Count.EqualTo(1));
        });

        var lockPath = result.Output[0].BaseObject as string;
        Assert.That(lockPath, Is.Not.Null.Or.Empty);

        var directory = Path.GetDirectoryName(lockPath!)?.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var tempRoot = Path.GetTempPath().TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

        Assert.Multiple(() => {
            Assert.That(directory, Is.EqualTo(tempRoot));
            Assert.That(Path.GetFileName(lockPath), Is.EqualTo("AMT_SetupPrinter_HPTest.lock"));
        });
    }

    [Test]
    public void GetLockPath_BindsPositionalArguments_ResourceThenScript() {
        var result = InvokeLockCommand("Get-LockPath", powerShell => {
            powerShell.AddArgument("Ricoh");
            powerShell.AddArgument("SetupPrinter");
        });

        Assert.Multiple(() => {
            Assert.That(result.ThrownException, Is.Null);
            Assert.That(result.Errors, Is.Empty);
            Assert.That(result.Output, Has.Count.EqualTo(1));
        });

        var lockPath = result.Output[0].BaseObject as string;
        Assert.Multiple(() => {
            Assert.That(lockPath, Is.Not.Null.Or.Empty);
            Assert.That(Path.GetFileName(lockPath), Is.EqualTo("AMT_SetupPrinter_Ricoh.lock"));
        });
    }

    [Test]
    public void WaitLockFile_WritesMetadataToLockFile() {
        var lockPath = CreateUniqueLockPath("metadata");
        FileStream? handle = null;

        try {
            var result = InvokeLockCommand("Wait-LockFile", powerShell => {
                powerShell.AddParameter("LockPath", lockPath);
                powerShell.AddParameter("LockOwner", "Ricoh");
            });

            Assert.Multiple(() => {
                Assert.That(result.ThrownException, Is.Null);
                Assert.That(result.Errors, Is.Empty);
                Assert.That(result.Output, Has.Count.EqualTo(1));
            });

            handle = result.Output[0].BaseObject as FileStream;
            Assert.That(handle, Is.Not.Null);

            var metadata = ReadLockMetadata(handle!);

            Assert.Multiple(() => {
                Assert.That(File.Exists(lockPath), Is.True);
                Assert.That(metadata, Does.Contain("PID="));
                Assert.That(metadata, Does.Contain("Owner=Ricoh"));
                Assert.That(metadata, Does.Match("Started=\\d{4}-\\d{2}-\\d{2}T"));
            });
        } finally {
            handle?.Dispose();
            TryDeleteFile(lockPath);
        }
    }

    [Test]
    public void WaitForLock_RetryFilter_HandlesContentionAndNonContentionFailures() {
        var sharingViolationWin32 = new IOException("Sharing violation", unchecked((int)0x80070020));
        var lockViolationWin32 = new IOException("Lock violation", unchecked((int)0x80070021));
        var linuxEagain = new IOException("Resource temporarily unavailable", 11);
        var macOsEagain = new IOException("Resource temporarily unavailable", 35);
        var sharingViolationMessage = new IOException("The process cannot access the file because it is being used by another process.");

        var diskFull = new IOException("There is not enough space on the disk.", unchecked((int)0x80070070));
        var pathTooLong = new PathTooLongException("Path is too long.");
        var fileNotFound = new FileNotFoundException("File not found.");
        var directoryNotFound = new DirectoryNotFoundException("Directory not found.");
        var genericIo = new IOException("Random I/O error.");

        Assert.Multiple(() => {
            Assert.That(LockOperations.ShouldRetryLockAcquisition(sharingViolationWin32), Is.True);
            Assert.That(LockOperations.ShouldRetryLockAcquisition(lockViolationWin32), Is.True);
            Assert.That(LockOperations.ShouldRetryLockAcquisition(linuxEagain), Is.True);
            Assert.That(LockOperations.ShouldRetryLockAcquisition(macOsEagain), Is.True);
            Assert.That(LockOperations.ShouldRetryLockAcquisition(sharingViolationMessage), Is.True);

            Assert.That(LockOperations.ShouldRetryLockAcquisition(diskFull), Is.False);
            Assert.That(LockOperations.ShouldRetryLockAcquisition(pathTooLong), Is.False);
            Assert.That(LockOperations.ShouldRetryLockAcquisition(fileNotFound), Is.False);
            Assert.That(LockOperations.ShouldRetryLockAcquisition(directoryNotFound), Is.False);
            Assert.That(LockOperations.ShouldRetryLockAcquisition(genericIo), Is.False);
        });
    }

    [Test]
    public void WaitLockFile_RetriesUntilLockAvailable() {
        var lockPath = CreateUniqueLockPath("retry");
        FileStream? blocker = null;
        FileStream? acquired = null;

        try {
            var directory = Path.GetDirectoryName(lockPath);
            if (!string.IsNullOrWhiteSpace(directory)) {
                Directory.CreateDirectory(directory);
            }

            blocker = new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);

            var releaseTask = Task.Run(async () => {
                await Task.Delay(250);
                blocker.Dispose();
                blocker = null;
            });

            var stopwatch = Stopwatch.StartNew();
            var result = InvokeLockCommand("Wait-LockFile", powerShell => {
                powerShell.AddParameter("LockPath", lockPath);
                powerShell.AddParameter("LockOwner", "RetryOwner");
            });
            stopwatch.Stop();

            releaseTask.GetAwaiter().GetResult();

            Assert.Multiple(() => {
                Assert.That(result.ThrownException, Is.Null);
                Assert.That(result.Errors, Is.Empty);
                Assert.That(result.Output, Has.Count.EqualTo(1));
            });

            acquired = result.Output[0].BaseObject as FileStream;
            Assert.Multiple(() => {
                Assert.That(acquired, Is.Not.Null);
                Assert.That(stopwatch.ElapsedMilliseconds, Is.GreaterThanOrEqualTo(900));
            });
        } finally {
            blocker?.Dispose();
            acquired?.Dispose();
            TryDeleteFile(lockPath);
        }
    }

    [Test]
    public void ReleaseLockFile_ClosesHandleAndRemovesFile() {
        var lockPath = CreateUniqueLockPath("release");
        FileStream? handle = null;

        try {
            var acquireResult = InvokeLockCommand("Wait-LockFile", powerShell => {
                powerShell.AddParameter("LockPath", lockPath);
                powerShell.AddParameter("LockOwner", "ReleaseOwner");
            });

            Assert.Multiple(() => {
                Assert.That(acquireResult.ThrownException, Is.Null);
                Assert.That(acquireResult.Errors, Is.Empty);
            });
            handle = acquireResult.Output[0].BaseObject as FileStream;
            Assert.That(handle, Is.Not.Null);

            var releaseResult = InvokeLockCommand("Release-LockFile", powerShell => {
                powerShell.AddParameter("LockHandle", handle);
                powerShell.AddParameter("LockPath", lockPath);
            });

            Assert.Multiple(() => {
                Assert.That(releaseResult.ThrownException, Is.Null);
                Assert.That(releaseResult.Errors, Is.Empty);
                Assert.That(File.Exists(lockPath), Is.False);
                Assert.That(handle!.SafeFileHandle.IsClosed, Is.True);
            });
        } finally {
            handle?.Dispose();
            TryDeleteFile(lockPath);
        }
    }

    [Test]
    public void InvokeUnderLock_ExecutesScriptBlockWithArgumentsAndCleansLock() {
        var resourceId = $"resource-{Guid.NewGuid():N}";
        var sanitizedResource = Sanitize(resourceId);

        var result = InvokeLockCommand("Invoke-UnderLock", powerShell => {
            powerShell.AddParameter("ResourceId", resourceId);
            powerShell.AddParameter(
                "ScriptBlock",
                ScriptBlock.Create(
                    "param($sanitizedResource, $value) " +
                    "$lock = Get-ChildItem -Path ([System.IO.Path]::GetTempPath()) -Filter (\"AMT_*_$sanitizedResource.lock\") | Select-Object -First 1 -ExpandProperty FullName; " +
                    "if (-not $lock) { throw 'lock-not-found' }; " +
                    "\"$lock|$value\""));
            powerShell.AddParameter("ArgumentList", new object[] { sanitizedResource, 7 });
        });

        Assert.Multiple(() => {
            Assert.That(result.ThrownException, Is.Null);
            Assert.That(result.Errors, Is.Empty);
            Assert.That(result.Output, Has.Count.EqualTo(1));
        });

        var payload = result.Output[0].BaseObject as string;
        Assert.That(payload, Is.Not.Null.Or.Empty);

        var parts = payload!.Split('|', 2);
        Assert.That(parts, Has.Length.EqualTo(2));

        var lockPath = parts[0];
        var value = parts[1];

        Assert.Multiple(() => {
            Assert.That(value, Is.EqualTo("7"));
            Assert.That(File.Exists(lockPath), Is.False);
            Assert.That(FindLockFilesForResource(sanitizedResource), Is.Empty);
        });
    }

    [Test]
    public void InvokeUnderLock_ReleasesLockWhenScriptBlockThrows() {
        var resourceId = $"resource-{Guid.NewGuid():N}";
        var sanitizedResource = Sanitize(resourceId);

        var result = InvokeLockCommand("Invoke-UnderLock", powerShell => {
            powerShell.AddParameter("ResourceId", resourceId);
            powerShell.AddParameter(
                "ScriptBlock",
                ScriptBlock.Create(
                    "param($sanitizedResource) " +
                    "$lock = Get-ChildItem -Path ([System.IO.Path]::GetTempPath()) -Filter (\"AMT_*_$sanitizedResource.lock\") | Select-Object -First 1 -ExpandProperty FullName; " +
                    "if ($lock) { Write-Output $lock }; " +
                    "throw 'intentional-lock-failure'"));
            powerShell.AddParameter("ArgumentList", new object[] { sanitizedResource });
        });

        Assert.Multiple(() => {
            Assert.That(result.ThrownException, Is.Not.Null);
            Assert.That(result.ThrownException!.Message, Does.Contain("intentional-lock-failure"));
        });

        var lockPath = result.Output.Count > 0 ? result.Output[0].BaseObject as string : null;
        if (!string.IsNullOrWhiteSpace(lockPath)) {
            Assert.That(File.Exists(lockPath), Is.False);
        }

        Assert.That(FindLockFilesForResource(sanitizedResource), Is.Empty);
    }

    private static CommandInvocationResult InvokeLockCommand(string commandName, Action<System.Management.Automation.PowerShell> configureCommand) {
        var initialSessionState = InitialSessionState.CreateDefault2();
        initialSessionState.Commands.Add(new SessionStateCmdletEntry(
            "Get-LockPath",
            typeof(GetLockPathCommand),
            helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry(
            "Wait-LockFile",
            typeof(WaitLockFileCommand),
            helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry(
            "Release-LockFile",
            typeof(ReleaseLockFileCommand),
            helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry(
            "Invoke-UnderLock",
            typeof(InvokeUnderLockCommand),
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

    private static string ReadLockMetadata(FileStream stream) {
        stream.Position = 0;
        using var reader = new StreamReader(stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: true, bufferSize: 1024, leaveOpen: true);
        return reader.ReadToEnd();
    }

    private static string CreateUniqueLockPath(string prefix) => Path.Combine(
        Path.GetTempPath(),
        "amt-lock-tests",
        $"{prefix}-{Guid.NewGuid():N}.lock");

    private static string[] FindLockFilesForResource(string sanitizedResource) {
        var pattern = $"AMT_*_{sanitizedResource}.lock";
        return Directory.GetFiles(Path.GetTempPath(), pattern, SearchOption.TopDirectoryOnly);
    }

    private static string Sanitize(string value) {
        var builder = new StringBuilder(value.Length);
        foreach (var character in value) {
            if (char.IsLetterOrDigit(character)) {
                builder.Append(character);
            }
        }

        return builder.ToString();
    }

    private static void TryDeleteFile(string path) {
        try {
            if (File.Exists(path)) {
                File.Delete(path);
            }
        } catch {
        }

        var directory = Path.GetDirectoryName(path);
        if (string.IsNullOrWhiteSpace(directory)) {
            return;
        }

        try {
            if (Directory.Exists(directory) && Directory.GetFileSystemEntries(directory).Length == 0) {
                Directory.Delete(directory);
            }
        } catch {
        }
    }

    private sealed record CommandInvocationResult(
        Collection<PSObject> Output,
        IReadOnlyList<ErrorRecord> Errors,
        RuntimeException? ThrownException);
}
