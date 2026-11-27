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
using AMT.PowerShell.Common.Commands.ModuleUtils;

namespace AMT.PowerShell.Common.Tests.Commands.ModuleUtils;

[TestFixture]
[NonParallelizable]
public sealed class ModuleUtilsCommandTests {
    private static readonly string MarkerTypeName = typeof(ExportMarkerType).FullName!;

    private static readonly Type[] MarkerTypes = [typeof(ExportMarkerType)];

    [TearDown]
    public void TearDown() {
        TypeAccelerators.Remove(MarkerTypeName);
        TypeAccelerators.Remove("System.Guid");
    }

    // ── Add-ModuleCallback ────────────────────────────────────────────────

    [Test]
    public void AddModuleCallback_ComposesExistingOnRemoveChain() {
        var logPath = Path.GetTempFileName();

        try {
            using var runspace = CreateRunspace();
            var module = NewDynamicModule(runspace, $"cb-{Guid.NewGuid():N}");

            var escaped = logPath.Replace("'", "''");
            Invoke(runspace, "Add-ModuleCallback", new Dictionary<string, object?> {
                ["Module"] = module,
                ["ScriptBlock"] = ScriptBlock.Create($"Add-Content -Path '{escaped}' -Value 'A'")
            });
            Invoke(runspace, "Add-ModuleCallback", new Dictionary<string, object?> {
                ["Module"] = module,
                ["ScriptBlock"] = ScriptBlock.Create($"Add-Content -Path '{escaped}' -Value 'B'")
            });

            InvokeOnRemove(module);

            Assert.That(File.ReadAllLines(logPath), Is.EqualTo(new[] { "A", "B" }));
        } finally {
            TryDeleteFile(logPath);
        }
    }

    [Test]
    public void AddModuleCallback_ThrowsWhenNotCalledFromModule() {
        using var runspace = CreateRunspace();

        var error = InvokeError(runspace, "Add-ModuleCallback", new Dictionary<string, object?> {
            ["ScriptBlock"] = ScriptBlock.Create("{}")
        });

        Assert.That(error.Message, Does.Contain("must be called from within a module"));
    }

    // ── Export-Types ──────────────────────────────────────────────────────

    [Test]
    public void ExportTypes_RegistersAndUnregistersTypeAccelerators() {
        using var runspace = CreateRunspace();
        var module = NewDynamicModule(runspace, $"et-{Guid.NewGuid():N}");

        try {
            Invoke(runspace, "Export-Types", new Dictionary<string, object?> {
                ["Module"] = module,
                ["Types"] = MarkerTypes
            });

            Assert.That(TypeAccelerators.Contains(MarkerTypeName), Is.True);

            InvokeOnRemove(module);

            Assert.That(TypeAccelerators.Contains(MarkerTypeName), Is.False);
        } finally {
            TypeAccelerators.Remove(MarkerTypeName);
        }
    }

    [Test]
    public void ExportTypes_ClobberFalse_ThrowsWhenAcceleratorAlreadyExists() {
        TypeAccelerators.Add(MarkerTypeName, typeof(ExportMarkerType));

        try {
            using var runspace = CreateRunspace();
            var module = NewDynamicModule(runspace, $"et-{Guid.NewGuid():N}");

            var error = InvokeError(runspace, "Export-Types", new Dictionary<string, object?> {
                ["Module"] = module,
                ["Types"] = MarkerTypes
            });

            Assert.That(error.Message, Does.Contain("Accelerator already exists"));
        } finally {
            TypeAccelerators.Remove(MarkerTypeName);
        }
    }

    [Test]
    public void ExportTypes_ClobberTrue_AllowsOverwritingExistingAccelerator() {
        TypeAccelerators.Add(MarkerTypeName, typeof(ExportMarkerType));

        try {
            using var runspace = CreateRunspace();
            var module = NewDynamicModule(runspace, $"et-{Guid.NewGuid():N}");

            Assert.DoesNotThrow(() => Invoke(runspace, "Export-Types", new Dictionary<string, object?> {
                ["Module"] = module,
                ["Types"] = MarkerTypes,
                ["Clobber"] = true
            }));

            Assert.That(TypeAccelerators.Contains(MarkerTypeName), Is.True);
        } finally {
            TypeAccelerators.Remove(MarkerTypeName);
        }
    }

    // ── TypeAccelerators reflection wrapper ───────────────────────────────

    [Test]
    public void ModuleUtils_TypeAccelerators_AddAndRemoveRoundTrip() {
        var name = $"__amt_roundtrip_{Guid.NewGuid():N}";
        TypeAccelerators.Add(name, typeof(ExportMarkerType));

        try {
            Assert.That(TypeAccelerators.Contains(name), Is.True);
            Assert.That(TypeAccelerators.Get()[name], Is.EqualTo(typeof(ExportMarkerType)));

            Assert.That(TypeAccelerators.Remove(name), Is.True);
            Assert.That(TypeAccelerators.Contains(name), Is.False);
        } finally {
            TypeAccelerators.Remove(name);
        }
    }

    // ── Default module resolution (caller module) ───────────────────────

    [Test]
    public void AddModuleCallback_DefaultModule_AttachesToCallerScriptModule() {
        var markerPath = Path.GetTempFileName();
        var moduleDir = CreateTempModuleDirectory();

        try {
            var escapedMarker = markerPath.Replace("'", "''");
            var modulePath = Path.Combine(moduleDir, "TestCallerModule.psm1");
            File.WriteAllText(
                modulePath,
                $"Add-ModuleCallback -ScriptBlock {{ Add-Content -Path '{escapedMarker}' -Value 'ran' }}");

            using var runspace = CreateRunspace();
            var module = ImportScriptModule(runspace, modulePath, "TestCallerModule");

            Assert.That(module.OnRemove, Is.Not.Null);
            module.OnRemove.Invoke();

            Assert.That(File.ReadAllLines(markerPath), Is.EqualTo(new[] { "ran" }));
        } finally {
            TryDeleteFile(markerPath);
            TryDeleteDirectory(moduleDir);
        }
    }

    [Test]
    public void ExportTypes_DefaultModule_AttachesCleanupToCallerScriptModule() {
        var moduleDir = CreateTempModuleDirectory();

        try {
            var modulePath = Path.Combine(moduleDir, "TestExportCallerModule.psm1");
            File.WriteAllText(modulePath, "Export-Types -Types @([System.Guid])");

            using var runspace = CreateRunspace();
            var module = ImportScriptModule(runspace, modulePath, "TestExportCallerModule");

            Assert.That(TypeAccelerators.Contains("System.Guid"), Is.True);
            Assert.That(module.OnRemove, Is.Not.Null);

            module.OnRemove.Invoke();

            Assert.That(TypeAccelerators.Contains("System.Guid"), Is.False);
        } finally {
            TypeAccelerators.Remove("System.Guid");
            TryDeleteDirectory(moduleDir);
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private static Runspace CreateRunspace() {
        var initialSessionState = InitialSessionState.CreateDefault2();
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Add-ModuleCallback", typeof(AddModuleCallbackCommand), null));
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Export-Types", typeof(ExportTypesCommand), null));

        var runspace = RunspaceFactory.CreateRunspace(initialSessionState);
        runspace.Open();
        return runspace;
    }

    private static PSModuleInfo NewDynamicModule(Runspace runspace, string name) {
        using var create = System.Management.Automation.PowerShell.Create();
        create.Runspace = runspace;
        create.AddCommand("New-Module")
            .AddParameter("Name", name)
            .AddParameter("ScriptBlock", ScriptBlock.Create("{}"));
        var createResult = create.Invoke();

        Assert.That(create.HadErrors, Is.False, $"New-Module failed: {FormatErrors(create.Streams.Error)}");
        Assert.That(createResult, Has.Count.EqualTo(1));
        Assert.That(createResult[0].BaseObject, Is.TypeOf<PSModuleInfo>());

        return (PSModuleInfo)createResult[0].BaseObject;
    }

    private static PSModuleInfo ImportScriptModule(Runspace runspace, string path, string name) {
        using var import = System.Management.Automation.PowerShell.Create();
        import.Runspace = runspace;
        import.AddCommand("Import-Module").AddParameter("Name", path).AddParameter("Force", true);
        var importResult = import.Invoke();

        Assert.That(import.HadErrors, Is.False, $"Import-Module failed: {FormatErrors(import.Streams.Error)}");

        using var get = System.Management.Automation.PowerShell.Create();
        get.Runspace = runspace;
        get.AddCommand("Get-Module").AddParameter("Name", name);
        var modules = get.Invoke();

        Assert.That(get.HadErrors, Is.False, $"Get-Module failed: {FormatErrors(get.Streams.Error)}");
        Assert.That(modules, Has.Count.EqualTo(1));
        return (PSModuleInfo)modules[0].BaseObject;
    }

    private static string CreateTempModuleDirectory() {
        var directory = Path.Combine(Path.GetTempPath(), $"amt-module-{Guid.NewGuid():N}");
        Directory.CreateDirectory(directory);
        return directory;
    }

    private static void TryDeleteDirectory(string path) {
        try { if (Directory.Exists(path)) Directory.Delete(path, recursive: true); } catch { }
    }

    private static void InvokeOnRemove(PSModuleInfo module) {
        var onRemove = module.OnRemove;
        Assert.That(onRemove, Is.Not.Null, "Expected module OnRemove callback to be registered.");
        onRemove.Invoke();
    }

    private static Collection<PSObject> Invoke(
        Runspace runspace,
        string commandName,
        IDictionary<string, object?>? parameters = null) {
        var result = InvokeCore(runspace, commandName, parameters);
        Assert.That(result.ThrownException, Is.Null,
            $"Command '{commandName}' failed:{Environment.NewLine}{result.ThrownException}");
        return result.Output;
    }

    private static RuntimeException InvokeError(
        Runspace runspace,
        string commandName,
        IDictionary<string, object?>? parameters = null) {
        var result = InvokeCore(runspace, commandName, parameters);
        Assert.That(result.ThrownException, Is.Not.Null,
            $"Command '{commandName}' was expected to fail but succeeded.");
        return result.ThrownException!;
    }

    private static InvocationResult InvokeCore(
        Runspace runspace,
        string commandName,
        IDictionary<string, object?>? parameters = null) {
        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddCommand(commandName);

        if (parameters is not null) {
            foreach (var parameter in parameters) {
                powerShell.AddParameter(parameter.Key, parameter.Value);
            }
        }

        var output = new Collection<PSObject>();
        RuntimeException? thrown = null;

        try {
            powerShell.Invoke(null, output);
        } catch (RuntimeException exception) {
            thrown = exception;
        }

        return new InvocationResult(output, [.. powerShell.Streams.Error], thrown);
    }

    private static string FormatErrors(IEnumerable<ErrorRecord> errors) =>
        string.Join(Environment.NewLine, errors.Select(error => error.ToString()));

    private static void TryDeleteFile(string path) {
        try { if (File.Exists(path)) File.Delete(path); } catch { }
    }

    private sealed record InvocationResult(
        Collection<PSObject> Output,
        IReadOnlyList<ErrorRecord> Errors,
        RuntimeException? ThrownException);

    // ── Test domain type ──────────────────────────────────────────────────

    private sealed class ExportMarkerType {
    }
}
