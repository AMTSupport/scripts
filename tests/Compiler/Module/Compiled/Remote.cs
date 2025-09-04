// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.IO.Compression;
using System.Management.Automation.Language;
using System.Reflection;
using Compiler.Module.Compiled;
using Compiler.Module.Resolvable;
using Compiler.Requirements;
using LanguageExt;

namespace Compiler.Test.Module.Compiled;

[TestFixture]
public class CompiledRemoteModuleTests {
    public static Lock WritingResourceLock = new();

    [Test, Repeat(10), Parallelizable]
    public async Task StringifyContent_ReturnsValidAst() {
        var module = await TestData.GetTestRemoteModule();
        var stringifiedContent = module.StringifyContent();
        Assert.Multiple(() => {
            var ast = Parser.ParseInput(stringifiedContent, out _, out var errors);
            Assert.That(errors, Is.Empty);
            Assert.That(ast, Is.Not.Null);
        });
    }

    [Test, Repeat(10), Parallelizable]
    public async Task StringifyContent_CanBeConvertedBack() {
        var module = await TestData.GetTestRemoteModule();
        var stringifiedContent = module.StringifyContent();
        var bytes = Convert.FromBase64String(stringifiedContent[1..^1]);

        Assert.Multiple(() => {
            Assert.That(bytes, Is.Not.Empty);

            using var zipArchive = new ZipArchive(new MemoryStream(module.ContentBytes.Value), ZipArchiveMode.Read, false);
            Assert.That(zipArchive, Is.Not.Null);
            Assert.That(zipArchive.Entries, Is.Not.Empty);
            Assert.That(zipArchive.Entries, Is.All.Property(nameof(ZipArchiveEntry.Length)).GreaterThan(0));
        });
    }

    public static class TestData {
        private static readonly Dictionary<string, string> TestableRemoteModules = new() {
            ["Microsoft.PowerShell.PSResourceGet"] = "1.0.5",
            ["PackageManagement"] = "1.4.8.1",
            ["PowerShellGet"] = "2.2.5",
            ["PSReadLine"] = "2.3.5"
        };

        public static async Task<CompiledRemoteModule> GetTestRemoteModule() {
            var random = TestContext.CurrentContext.Random;
            var (moduleName, moduleVersion) = TestableRemoteModules.ElementAt(random.Next(0, TestableRemoteModules.Count));
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
            resolvable.CachedFile = Prelude.Atom(Either<Option<string>, Task<Option<string>>>.Left(tmpFile.AsOption()));

            var module = (await resolvable.IntoCompiled(parent)).Unwrap() as CompiledRemoteModule;
            CompiledUtils.EnsureMockHasParent(module!);
            return module!;
        }
    }
}
