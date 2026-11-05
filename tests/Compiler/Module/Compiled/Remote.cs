// Copyright (c) 2024, 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections;
using System.IO.Compression;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Reflection;
using System.Text;
using Compiler.Module.Compiled;
using Compiler.Module.Resolvable;
using Compiler.Requirements;

namespace Compiler.Test.Module.Compiled;

[TestFixture]
public class CompiledRemoteModuleTests {
    private static readonly Lock WritingResourceLock = new();

    [Test, Repeat(3), Parallelizable]
    public async Task StringifyContent_ReturnsValidAst() {
        var module = await TestData.GetTestRemoteModule();
        var stringifiedContent = module.StringifyContent().Unwrap();
        Assert.Multiple(() => {
            var ast = Parser.ParseInput(stringifiedContent, out _, out var errors);
            Assert.That(errors, Is.Empty);
            Assert.That(ast, Is.Not.Null);
        });
    }

    [Test, Repeat(3), Parallelizable]
    public async Task StringifyContent_CanBeConvertedBack() {
        var module = await TestData.GetTestRemoteModule();
        var stringifiedContent = module.StringifyContent().Unwrap();
        var bytes = Convert.FromBase64String(stringifiedContent[1..^1]);

        Assert.Multiple(() => {
            Assert.That(bytes, Is.Not.Empty);
            Assert.That(bytes, Is.EqualTo(module.GetContentBytes().Unwrap()));

            using var zipArchive = new ZipArchive(new MemoryStream(bytes), ZipArchiveMode.Read, false);
            Assert.That(zipArchive, Is.Not.Null);
            Assert.That(zipArchive.Entries, Is.Not.Empty);
            Assert.That(zipArchive.Entries, Is.All.Property(nameof(ZipArchiveEntry.Length)).GreaterThan(0));
        });
    }

    [Test]
    public async Task StringifyContent_RenamesEmbeddedArchiveManifestToHash() {
        var module = await TestData.GetTestRemoteModule("PowerShellGet");
        var moduleName = module.ModuleSpec.Name;
        var originalBytes = module.GetContentBytes().Unwrap();

        using var originalArchive = new ZipArchive(new MemoryStream(originalBytes), ZipArchiveMode.Read, false);
        var originalManifestEntry = originalArchive.Entries.FirstOrDefault(entry => entry.FullName.Equals($"{moduleName}.psd1", StringComparison.OrdinalIgnoreCase));
        Assert.That(originalManifestEntry, Is.Not.Null);

        var checkedOriginalVersionedModuleTables = 0;
        if (originalManifestEntry is not null) {
            using var originalManifestStream = originalManifestEntry.Open();
            using var originalReader = new StreamReader(originalManifestStream, Encoding.UTF8, true);
            var originalManifestText = originalReader.ReadToEnd();
            var originalManifest = ParseManifest(originalManifestText);

            if (originalManifest["RequiredModules"] is IEnumerable requiredModulesEnumerable and not string) {
                foreach (var requiredModule in requiredModulesEnumerable) {
                    var requiredModuleValue = requiredModule is PSObject psObject
                        ? psObject.BaseObject
                        : requiredModule;
                    if (requiredModuleValue is IDictionary requiredModuleTable
                        && (requiredModuleTable.Contains("ModuleVersion")
                            || requiredModuleTable.Contains("RequiredVersion")
                            || requiredModuleTable.Contains("MaximumVersion"))) {
                        checkedOriginalVersionedModuleTables++;
                    }
                }
            }
        }

        Assert.That(checkedOriginalVersionedModuleTables, Is.GreaterThan(0));

        var stringifiedContent = module.StringifyContent().Unwrap();
        var hash = module.GetNameHash().Unwrap();
        var bytes = Convert.FromBase64String(stringifiedContent[1..^1]);

        using var zipArchive = new ZipArchive(new MemoryStream(bytes), ZipArchiveMode.Read, false);
        var entryNames = zipArchive.Entries.Select(entry => entry.FullName).ToArray();
        var manifestEntry = zipArchive.Entries.FirstOrDefault(entry => entry.FullName.Equals($"{hash}.psd1", StringComparison.OrdinalIgnoreCase));

        Assert.Multiple(() => {
            Assert.That(entryNames, Has.Some.EqualTo($"{hash}.psd1"));
            Assert.That(entryNames, Has.All.Not.EqualTo($"{moduleName}.psd1"));
            Assert.That(manifestEntry, Is.Not.Null);
            if (manifestEntry is not null) {
                using var manifestStream = manifestEntry.Open();
                using var reader = new StreamReader(manifestStream, Encoding.UTF8, true);
                var manifestText = reader.ReadToEnd();
                var parsedManifest = ParseManifest(manifestText);
                var requiredModules = parsedManifest["RequiredModules"];

                if (requiredModules is IEnumerable requiredModulesEnumerable and not string) {
                    foreach (var requiredModule in requiredModulesEnumerable) {
                        var requiredModuleValue = requiredModule is PSObject psObject
                            ? psObject.BaseObject
                            : requiredModule;
                        if (requiredModuleValue is IDictionary requiredModuleTable) {
                            Assert.That(requiredModuleTable.Contains("RequiredVersion"), Is.False);
                        }
                    }
                }
            }
        });
    }

    private static Hashtable ParseManifest(string manifestText) {
        using var pwsh = PowerShell.Create();
        _ = pwsh.AddScript(manifestText);
        var outputs = pwsh.Invoke();

        if (pwsh.HadErrors || outputs.Count == 0 || outputs[0].BaseObject is not Hashtable manifest) {
            throw new AssertionException("Expected parsed manifest hashtable from rewritten PSD1 output.");
        }

        return manifest;
    }

    public static class TestData {
        private static readonly Dictionary<string, string> TestableRemoteModules = new() {
            ["Microsoft.PowerShell.PSResourceGet"] = "1.0.5",
            ["PackageManagement"] = "1.4.8.1",
            ["PowerShellGet"] = "2.2.5",
            ["PSReadLine"] = "2.3.5"
        };

        public static async Task<CompiledRemoteModule> GetTestRemoteModule(string? requiredModuleName = null) {
            var random = TestContext.CurrentContext.Random;
            string moduleName;
            string moduleVersion;
            if (requiredModuleName is null) {
                var selectedModule = TestableRemoteModules.ElementAt(random.Next(0, TestableRemoteModules.Count));
                moduleName = selectedModule.Key;
                moduleVersion = selectedModule.Value;
            } else {
                moduleName = requiredModuleName;
                moduleVersion = TestableRemoteModules[requiredModuleName];
            }

            var moduleSpec = new ModuleSpec(moduleName, requiredVersion: new Version(moduleVersion));
            var parent = new ResolvableParent(TestContext.CurrentContext.TestDirectory);
            var resolvable = new ResolvableRemoteModule(moduleSpec);

            var info = Assembly.GetExecutingAssembly().GetName();
            using var nupkgStream = Assembly.GetExecutingAssembly().GetManifestResourceStream($"{info.Name}.Resources.{moduleName}.{moduleVersion}.nupkg")!;
            var tmpDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
            var tmpFile = Path.Combine(tmpDir, $"{moduleName}.{moduleVersion}.nupkg");
            lock (WritingResourceLock) {
                if (!Directory.Exists(tmpDir)) Directory.CreateDirectory(tmpDir);

                using var fileStream = new FileStream(tmpFile, FileMode.CreateNew, FileAccess.Write);
                nupkgStream.CopyTo(fileStream);
            }
            resolvable.CachedFile = tmpFile.AsOption();

            var module = (await resolvable.IntoCompiled(parent)).Unwrap() as CompiledRemoteModule;
            CompiledUtils.EnsureMockHasParent(module!);
            return module!;
        }
    }
}
