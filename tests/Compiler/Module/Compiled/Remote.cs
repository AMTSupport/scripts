// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.IO.Compression;
using System.Management.Automation.Language;
using System.Reflection;
using Compiler.Module.Compiled;
using Compiler.Requirements;
using Moq;

namespace Compiler.Test.Module.Compiled;

[TestFixture]
public class CompiledRemoteModuleTests {
    [Test, Repeat(10), Parallelizable]
    public void StringifyContent_ReturnsValidAst() {
        var module = TestData.GetTestRemoteModule();
        var stringifiedContent = module.StringifyContent();
        Assert.Multiple(() => {
            var ast = Parser.ParseInput(stringifiedContent, out _, out var errors);
            Assert.That(errors, Is.Empty);
            Assert.That(ast, Is.Not.Null);
        });
    }

    [Test, Repeat(10), Parallelizable]
    public void StringifyContent_CanBeConvertedBack() {
        // Convert the base64 string back to a byte array, then into a memory stream, then into a zip archive.
        var module = TestData.GetTestRemoteModule();
        var stringifiedContent = module.StringifyContent();
        var bytes = Convert.FromBase64String(stringifiedContent[1..^1]);

        Assert.Multiple(() => {
            Assert.That(bytes, Is.Not.Empty);
            Assert.That(bytes, Is.EqualTo(module.ContentBytes.Value));

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

        public static CompiledRemoteModule GetTestRemoteModule() {
            var random = TestContext.CurrentContext.Random;
            var (moduleName, moduleVersion) = TestableRemoteModules.ElementAt(random.Next(0, TestableRemoteModules.Count));
            var moduleSpec = new ModuleSpec(moduleName, requiredVersion: new Version(moduleVersion));
            var requirementGroup = new RequirementGroup();

            var info = Assembly.GetExecutingAssembly().GetName();
            using var nupkgStream = Assembly.GetExecutingAssembly().GetManifestResourceStream($"{info.Name}.Resources.{moduleName}.{moduleVersion}.nupkg")!;
            var bytes = new byte[nupkgStream.Length];
            nupkgStream.ReadExactly(bytes);

            var mock = new Mock<CompiledRemoteModule>(moduleSpec, requirementGroup, bytes) {
                CallBase = true
            };

            return mock.Object;
        }
    }
}
