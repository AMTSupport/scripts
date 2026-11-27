// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using AMT.PowerShell.Common.Commands;
using AMT.PowerShell.Common.Module;

namespace AMT.PowerShell.Common.Tests.Commands.Flag;

[TestFixture]
[NonParallelizable]
public sealed class FlagCommandTests {
    [TearDown]
    public void TearDown() {
        RunningFlag.WarningWriterOverride = null;
        RebootFlag.LinuxUptimeFileExistsOverride = null;
        RebootFlag.LinuxUptimeReaderOverride = null;
        RebootFlag.TickCount64ProviderOverride = null;
        RebootFlag.TickCountProviderOverride = null;
        RebootFlag.UtcNowProviderOverride = null;
    }

    [Test]
    public void GetFlagPath_ReturnsExpectedPathAndCreatesFolder() {
        var context = $"flag-path-{Guid.NewGuid():N}";
        var expectedFolder = Path.Combine(Path.GetTempPath(), "Flags");
        var expectedPath = Path.Combine(expectedFolder, $"{context}.flag");

        try {
            var actualPath = InvokeSingle<string>(
                "Get-FlagPath",
                new Dictionary<string, object?> {
                    ["Context"] = context
                });

            Assert.Multiple(() => {
                Assert.That(actualPath, Is.EqualTo(expectedPath));
                Assert.That(Directory.Exists(expectedFolder), Is.True);
            });
        } finally {
            TryDeleteFile(expectedPath);
        }
    }

    [Test]
    public void GetFlag_ReturnedObjectHasSetGetRemoveExistsParity() {
        var context = $"flag-base-{Guid.NewGuid():N}";
        var flag = InvokeSingle<AMT.PowerShell.Common.Module.Flag>(
            "Get-Flag",
            new Dictionary<string, object?> {
                ["Context"] = context
            });

        try {
            Assert.That(flag.Exists(), Is.False);

            flag.Set("test-data");
            Assert.Multiple(() => {
                Assert.That(flag.Exists(), Is.True);
                Assert.That(flag.GetData(), Is.EqualTo("test-data"));
            });

            flag.Set(null);
            Assert.That(flag.GetData(), Is.Null);

            Assert.DoesNotThrow(() => flag.Remove());
            Assert.That(flag.Exists(), Is.False);
            Assert.DoesNotThrow(() => flag.Remove());
        } finally {
            flag.Remove();
        }
    }

    [Test]
    public void GetRunningFlag_StoresCurrentPidAndRemovesStaleFlag() {
        var flag = InvokeSingle<RunningFlag>("Get-RunningFlag");

        try {
            flag.Remove();
            flag.Set("ignored-data");

            var data = flag.GetData();
            var isParsed = int.TryParse(data?.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var currentPid);

            Assert.Multiple(() => {
                Assert.That(isParsed, Is.True);
                Assert.That(currentPid, Is.EqualTo(Environment.ProcessId));
                Assert.That(flag.IsRunning(), Is.True);
            });

            File.WriteAllText(flag.FlagPath, int.MaxValue.ToString(CultureInfo.InvariantCulture));

            Assert.Multiple(() => {
                Assert.That(flag.IsRunning(), Is.False);
                Assert.That(flag.Exists(), Is.False);
            });
        } finally {
            flag.Remove();
        }
    }

    [Test]
    public void RunningFlag_Set_WarnsWhenDataProvided() {
        var flag = new RunningFlag();
        var capturedWarnings = new List<string>();
        RunningFlag.WarningWriterOverride = capturedWarnings.Add;

        try {
            flag.Set("some-custom-data");
            Assert.Multiple(() => {
                Assert.That(capturedWarnings, Has.Count.EqualTo(1));
                Assert.That(capturedWarnings[0], Does.Contain("Data is ignored for RunningFlag"));
            });

            capturedWarnings.Clear();
            flag.Set(null);
            Assert.That(capturedWarnings, Is.Empty);
        } finally {
            flag.Remove();
        }
    }

    [Test]
    public void GetRebootFlag_RequiredUsesBootTimeCheckWithoutThrowing() {
        var flag = InvokeSingle<RebootFlag>("Get-RebootFlag");

        try {
            flag.Remove();
            Assert.That(flag.Required(), Is.False);

            flag.Set(null);
            Assert.DoesNotThrow(() => _ = flag.Required());
            Assert.That(flag.Required(), Is.True);

            File.SetLastWriteTimeUtc(flag.FlagPath, DateTime.UtcNow.AddYears(-5));
            Assert.That(flag.Required(), Is.False);
        } finally {
            flag.Remove();
        }
    }

    [Test]
    public void RebootFlag_ResolveBootTimeUtc_PrefersLinuxUptimeThenTickCount64ThenTickCount32() {
        var referenceNow = new DateTimeOffset(2026, 11, 5, 12, 0, 0, TimeSpan.Zero);
        RebootFlag.UtcNowProviderOverride = () => referenceNow;

        // 1) Linux uptime present
        RebootFlag.LinuxUptimeFileExistsOverride = () => true;
        RebootFlag.LinuxUptimeReaderOverride = () => "120.5 450.0";

        var linuxBootTime = RebootFlag.ResolveBootTimeUtc();
        Assert.That(linuxBootTime, Is.EqualTo(referenceNow - TimeSpan.FromSeconds(120.5)));

        // 2) Linux uptime absent -> TickCount64 used
        RebootFlag.LinuxUptimeFileExistsOverride = () => false;
        RebootFlag.TickCount64ProviderOverride = () => 60000;

        var tick64BootTime = RebootFlag.ResolveBootTimeUtc();
        Assert.That(tick64BootTime, Is.EqualTo(referenceNow - TimeSpan.FromMilliseconds(60000)));

        // 3) TickCount64 unavailable (e.g. MissingMemberException) -> TickCount32 fallback
        RebootFlag.TickCount64ProviderOverride = () => throw new MissingMemberException("Environment", "TickCount64");
        RebootFlag.TickCountProviderOverride = () => 30000;

        var tick32BootTime = RebootFlag.ResolveBootTimeUtc();
        Assert.That(tick32BootTime, Is.EqualTo(referenceNow - TimeSpan.FromMilliseconds(30000)));
    }

    private static T InvokeSingle<T>(string commandName, IDictionary<string, object?>? parameters = null) {
        var results = InvokeCommand(commandName, parameters);

        Assert.That(results, Has.Count.EqualTo(1));
        Assert.That(results[0].BaseObject, Is.TypeOf<T>());

        return (T)results[0].BaseObject;
    }

    private static Collection<PSObject> InvokeCommand(string commandName, IDictionary<string, object?>? parameters = null) {
        var initialSessionState = InitialSessionState.CreateDefault2();
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Get-FlagPath", typeof(GetFlagPathCommand), helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Get-Flag", typeof(GetFlagCommand), helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Get-RunningFlag", typeof(GetRunningFlagCommand), helpFileName: null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Get-RebootFlag", typeof(GetRebootFlagCommand), helpFileName: null));

        using var runspace = RunspaceFactory.CreateRunspace(initialSessionState);
        runspace.Open();

        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddCommand(commandName);

        if (parameters is not null) {
            foreach (var parameter in parameters) {
                powerShell.AddParameter(parameter.Key, parameter.Value);
            }
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

    private static void TryDeleteFile(string path) {
        try {
            if (File.Exists(path)) {
                File.Delete(path);
            }
        } catch {
        }
    }
}
