// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections;
using System.IO.Compression;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Text;
using AMT.PowerShell.Common.Commands;
using AMT.PowerShell.Common.Module;

namespace AMT.PowerShell.Common.Tests.Commands;

[TestFixture]
[NonParallelizable]
public sealed class InitializeCompiledRuntimeCommandTests {
    [Test]
    public void InitializeCompiledRuntime_UsesPowerShellMajorVersionForDefaultRoot() {
        var getPowerShellMajorVersion = typeof(InitializeCompiledRuntimeCommand)
            .GetMethod("GetPowerShellMajorVersion", BindingFlags.Static | BindingFlags.NonPublic);
        var getDefaultModuleRoot = typeof(InitializeCompiledRuntimeCommand)
            .GetMethod("GetDefaultModuleRoot", BindingFlags.Static | BindingFlags.NonPublic);

        Assert.Multiple(() => {
            Assert.That(getPowerShellMajorVersion, Is.Not.Null);
            Assert.That(getDefaultModuleRoot, Is.Not.Null);

            var resolvedMajorVersion = (int)getPowerShellMajorVersion!.Invoke(null, null)!;
            var defaultModuleRoot = (string)getDefaultModuleRoot!.Invoke(null, [resolvedMajorVersion])!;
            var expectedMajorVersion = PSVersionInfo.PSVersion.Major;
            var expectedSuffix = $"{Path.DirectorySeparatorChar}PS{expectedMajorVersion}";

            Assert.That(resolvedMajorVersion, Is.EqualTo(expectedMajorVersion));
            Assert.That(defaultModuleRoot, Does.EndWith(expectedSuffix));
        });
    }

    [Test]
    public void InitializeCompiledRuntime_DoesNotDuplicatePrivateModuleRoot() {
        var prependModulePath = typeof(InitializeCompiledRuntimeCommand)
            .GetMethod("PrependModulePath", BindingFlags.Static | BindingFlags.NonPublic);
        var privateModuleRoot = Path.Combine(Path.GetTempPath(), $"amt-cs-tests-{Guid.NewGuid():N}");
        var anotherModuleRoot = Path.Combine(Path.GetTempPath(), $"amt-cs-tests-{Guid.NewGuid():N}");
        var originalPath = string.Join(Path.PathSeparator, [privateModuleRoot, anotherModuleRoot]);

        Assert.That(prependModulePath, Is.Not.Null);

        var privatePath = (string)prependModulePath!.Invoke(null, [originalPath, privateModuleRoot])!;
        var modulePathSegments = privatePath.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries);

        Assert.Multiple(() => {
            Assert.That(privatePath, Is.EqualTo(originalPath));
            Assert.That(modulePathSegments.Count(segment => string.Equals(segment, privateModuleRoot, StringComparison.OrdinalIgnoreCase)), Is.EqualTo(1));
        });
    }

    [Test]
    public void InitializeCompiledRuntime_ZipExtractionIsIdempotent() {
        var privateModuleRoot = CreateUniqueDirectory();
        var originalEnvironmentPath = Environment.GetEnvironmentVariable("PSModulePath");
        const string moduleName = "ZipModule";
        const string moduleHash = "B8EE4D";
        var embeddedModules = new[] { BuildEmbeddedZipModule(moduleName, moduleHash, "content/module.psm1", "'from-archive'") };
        var moduleFolder = Path.Combine(privateModuleRoot, $"{moduleName}-{moduleHash}");
        var extractedModuleFile = Path.Combine(moduleFolder, "content", "module.psm1");
        var readyMarkerPath = Path.Combine(moduleFolder, ".ready");

        try {
            Environment.SetEnvironmentVariable("PSModulePath", string.Empty);

            var firstRunState = InvokeInitializeCompiledRuntime(embeddedModules, privateModuleRoot);
            Assert.That(firstRunState.PrivatePSModulePath, Does.StartWith(privateModuleRoot));

            Assert.Multiple(() => {
                Assert.That(File.Exists(extractedModuleFile), Is.True);
                Assert.That(File.Exists(readyMarkerPath), Is.True);
                Assert.That(Directory.GetFiles(moduleFolder, "*.zip", SearchOption.TopDirectoryOnly), Is.Empty);
            });

            File.WriteAllText(extractedModuleFile, "mutated-content", new UTF8Encoding(false));

            var secondRunState = InvokeInitializeCompiledRuntime(embeddedModules, privateModuleRoot);

            Assert.Multiple(() => {
                Assert.That(secondRunState.PrivatePSModulePath.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries).First(), Is.EqualTo(privateModuleRoot));
                Assert.That(File.ReadAllText(extractedModuleFile), Is.EqualTo("mutated-content"));
                Assert.That(File.Exists(readyMarkerPath), Is.True);
                Assert.That(Directory.GetFiles(moduleFolder, "*.zip", SearchOption.TopDirectoryOnly), Is.Empty);
            });
        } finally {
            Environment.SetEnvironmentVariable("PSModulePath", originalEnvironmentPath);
            TryDeleteDirectory(privateModuleRoot);
        }
    }

    private static RuntimeState InvokeInitializeCompiledRuntime(Hashtable[] embeddedModules, string? privateModuleRoot) {
        var initialSessionState = InitialSessionState.CreateDefault2();
        initialSessionState.Commands.Add(new SessionStateCmdletEntry(
            "Initialize-AMTCompiledRuntime",
            typeof(InitializeCompiledRuntimeCommand),
            helpFileName: null));

        using var runspace = RunspaceFactory.CreateRunspace(initialSessionState);
        runspace.Open();

        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddCommand("Initialize-AMTCompiledRuntime");
        powerShell.AddParameter("EmbeddedModules", embeddedModules);
        if (!string.IsNullOrWhiteSpace(privateModuleRoot)) {
            powerShell.AddParameter("PrivateModuleRoot", privateModuleRoot);
        }

        var results = powerShell.Invoke();

        if (powerShell.HadErrors) {
            var errorText = string.Join(
                Environment.NewLine,
                powerShell.Streams.Error.Select(error => error.ToString()));
            throw new AssertionException($"Initialize-AMTCompiledRuntime failed:{Environment.NewLine}{errorText}");
        }

        Assert.That(results, Has.Count.EqualTo(1));
        Assert.That(results[0].BaseObject, Is.TypeOf<RuntimeState>());

        return (RuntimeState)results[0].BaseObject;
    }

    private static Hashtable BuildEmbeddedZipModule(string name, string hash, string archivePath, string fileContent) {
        using var stream = new MemoryStream();
        using (var archive = new ZipArchive(stream, ZipArchiveMode.Create, leaveOpen: true)) {
            var entry = archive.CreateEntry(archivePath);
            using var writer = new StreamWriter(entry.Open(), new UTF8Encoding(false));
            writer.Write(fileContent);
        }

        return new Hashtable {
            ["Name"] = name,
            ["Hash"] = hash,
            ["Type"] = "Zip",
            ["Content"] = Convert.ToBase64String(stream.ToArray())
        };
    }

    private static string CreateUniqueDirectory() {
        var path = Path.Combine(Path.GetTempPath(), $"amt-cs-tests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }

    private static void TryDeleteDirectory(string path) {
        try {
            if (Directory.Exists(path)) {
                Directory.Delete(path, recursive: true);
            }
        } catch {
        }
    }
}
