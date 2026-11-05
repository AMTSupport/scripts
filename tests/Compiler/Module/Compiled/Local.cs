// Copyright (c) 2024, 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.IO.Compression;
using System.Management.Automation.Language;
using System.Text;
using System.Text.RegularExpressions;
using Compiler.Module.Compiled;
using Compiler.Requirements;
using Compiler.Text;
using Moq;
using RealCompiled = Compiler.Module.Compiled.Compiled;

namespace Compiler.Test.Module.Compiled;

[TestFixture]
public partial class CompiledLocalModuleTests {
    [Test, Repeat(10), Parallelizable]
    public async Task StringifyContent_ReturnsValidAstContent() {
        var module = await TestData.GetRandomCompiledModule();
        var stringifiedContent = module.StringifyContent().Unwrap();
        Assert.Multiple(() => {
            var ast = Parser.ParseInput(stringifiedContent, out _, out var errors);
            Assert.That(errors, Is.Empty);
            Assert.That(ast, Is.Not.Null);
        });
    }

    [Test, Parallelizable]
    public void HashChanges(
        [Values("Hello, World!")] string scriptOneHello,
        [Values("Hello, World!", "Hello, Other World!")] string scriptTwoHello
    ) => Assert.Multiple(() => {
        var scriptOne = TestData.CreateModule<CompiledScript>($"Write-Host '{scriptOneHello}';");
        var scriptTwo = TestData.CreateModule<CompiledScript>($"Write-Host '{scriptTwoHello}';");

        var scriptOneHash = scriptOne.ComputedHash().Unwrap();
        var scriptTwoHash = scriptTwo.ComputedHash().Unwrap();
        var expression = scriptOneHello == scriptTwoHello ? Is.EqualTo(scriptTwoHash) : Is.Not.EqualTo(scriptTwoHash);
        Assert.That(scriptOneHash, expression, "Hashes should be the same if the content is the same.");

        if (scriptOneHello == scriptTwoHello) {
            var oldHash = scriptOneHash;

            var moduleContent = "Write-Host 'Hello, World!';";
            var randomName = TestContext.CurrentContext.Random.GetString(6);
            var localDependency = TestData.CreateModule<CompiledLocalModule>(moduleContent, randomName);
            CompiledUtils.AddDependency(scriptOne, localDependency);
            Assert.That(scriptOne.ComputedHash().Unwrap(), Is.Not.EqualTo(oldHash), "Hash should change when a dependency is added.");
            Assert.That(scriptOne.ComputedHash().Unwrap(), Is.Not.EqualTo(scriptTwoHash), "Hashes should differ when a dependency is added.");

            CompiledUtils.AddDependency(scriptTwo, localDependency);
            Assert.That(scriptOne.ComputedHash().Unwrap(), Is.EqualTo(scriptTwo.ComputedHash().Unwrap()), "Hashes should not differ when the dependencies are the same.");

            // Check that a nested dependency changes the hash of the top module
            var moduleDependencyOne = TestData.CreateModule<CompiledLocalModule>(moduleContent, randomName);
            var moduleDependencyTwo = TestData.CreateModule<CompiledLocalModule>(moduleContent, randomName);
            var nestedDependencyOne = TestData.CreateModule<CompiledLocalModule>("Write-Host 'Hello, Nested World!';");

            CompiledUtils.AddDependency(scriptOne, moduleDependencyOne);
            CompiledUtils.AddDependency(scriptTwo, moduleDependencyTwo);
            CompiledUtils.AddDependency(moduleDependencyOne, nestedDependencyOne);
            CompiledUtils.AddDependency(moduleDependencyTwo, nestedDependencyOne);
            Assert.That(moduleDependencyOne.ComputedHash().Unwrap(), Is.EqualTo(moduleDependencyTwo.ComputedHash().Unwrap()), "Hashes should be the same if the dependencies are the same.");
            Assert.That(scriptOne.ComputedHash().Unwrap(), Is.EqualTo(scriptTwo.ComputedHash().Unwrap()), "Hashes should not differ when a nested dependency matches.");

            var nestedDependencyTwo = TestData.CreateModule<CompiledLocalModule>("Write-Host 'Hello, Other Nested World!';");
            CompiledUtils.RemoveDependency(moduleDependencyTwo, nestedDependencyOne);
            CompiledUtils.AddDependency(moduleDependencyTwo, nestedDependencyTwo);
            Assert.That(moduleDependencyOne.ComputedHash().Unwrap(), Is.Not.EqualTo(moduleDependencyTwo.ComputedHash().Unwrap()), "Hashes should differ when the dependency changes.");
            Assert.That(scriptOne.ComputedHash().Unwrap(), Is.Not.EqualTo(scriptTwo.ComputedHash().Unwrap()), "Hashes should differ when a nested dependency changes.");
        }
    });

    [Test]
    public void StringifyContent_EmbeddedHashedImportUsesPlainModuleReference() {
        var root = TestData.CreateModule<CompiledScript>("Write-Host 'Root';");
        var module = TestData.CreateModule<CompiledLocalModule>("Write-Host 'Dep';", "DepModule");
        var remoteDependency = CompiledRemoteModuleTests.TestData.GetTestRemoteModule().GetAwaiter().GetResult();

        CompiledUtils.AddDependency(root, module);
        CompiledUtils.AddDependency(module, remoteDependency);

        var output = module.StringifyContent().Unwrap();
        var bytes = Convert.FromBase64String(StripQuotedBase64(output));
        var decodedOutput = DecompressGzip(bytes);
        var remoteHash = remoteDependency.GetNameHash().Unwrap();

        Assert.Multiple(() => {
            Assert.That(decodedOutput, Does.Contain($"Using module '{remoteHash}'"));
            Assert.That(decodedOutput.Contains("RequiredVersion", StringComparison.Ordinal), Is.False);
            Assert.That(decodedOutput.Contains("MaximumVersion", StringComparison.Ordinal), Is.False);
            Assert.That(decodedOutput.Contains("ModuleVersion", StringComparison.Ordinal), Is.False);
            Assert.That(decodedOutput.Contains("GUID", StringComparison.Ordinal), Is.False);
        });
    }

    [Test]
    public void StringifyContent_UnicodeLocalModuleUsesAsciiSafePayloadContract() {
        var moduleContent = "function Invoke-Unicode { '📦-🗑️-🔄-Ω' }";
        var module = TestData.CreateModule<CompiledLocalModule>(moduleContent, "UnicodeModule");
        var output = module.StringifyContent().Unwrap();

        Assert.Multiple(() => {
            Assert.That(output, Does.Not.Contain("📦"));
            Assert.That(output, Does.Not.Contain("🗑️"));
            Assert.That(output, Does.Not.Contain("🔄"));
            Assert.That(output, Does.Not.Contain("Ω"));
            Assert.That(output, Is.EqualTo(Encoding.ASCII.GetString(Encoding.ASCII.GetBytes(output))));
            Assert.That(output, Does.Match("^[\x00-\x7F]+$"));
            Assert.That(output, Does.Match("['\"]?[A-Za-z0-9+/=]+['\"]?"));
        });
    }

    [Test]
    public void StringifyContent_LocalTextPayloadUsesGzipRoundtrip() {
        var moduleContent = "function Invoke-GzipLocal { 'local gzip payload' }";
        var module = TestData.CreateModule<CompiledLocalModule>(moduleContent, "GzipLocalModule");
        var output = module.StringifyContent().Unwrap();
        var bytes = Convert.FromBase64String(StripQuotedBase64(output));

        Assert.Multiple(() => {
            Assert.That(bytes, Is.Not.Empty);
            Assert.That(DecompressGzip(bytes), Does.Contain("Invoke-GzipLocal"));
            Assert.That(DecompressGzip(bytes), Does.Contain("local gzip payload"));
        });
    }

    [Test]
    public void StringifyContent_LocalTextPayloadMetadataUsesPowerShellObject() {
        var moduleContent = "function Invoke-GzipLocal { 'local gzip payload' }";
        var root = TestData.CreateModule<CompiledScript>("Write-Host 'Root';");
        var module = TestData.CreateModule<CompiledLocalModule>(moduleContent, "GzipLocalModule");
        CompiledUtils.AddDependency(root, module);
        var output = module.GetPowerShellObject().Unwrap().ToString();

        Assert.Multiple(() => {
            Assert.That(output, Does.Contain("Compression = 'GZip'"));
            Assert.That(output, Does.Contain("Type = 'UTF8String'"));
        });
    }

    [Test, NonParallelizable]
    public void StringifyContent_LocalTextPayloadNoneModeEmitsPlainPowerShellText() {
        try {
            CompilerSettings.ConfigureEmbeddedLocalTextCompression("none");
            var root = TestData.CreateModule<CompiledScript>("Write-Host 'Root';");
            var moduleContent = "function Invoke-PlainLocal { 'local plain payload' }";
            var module = TestData.CreateModule<CompiledLocalModule>(moduleContent, "PlainLocalModule");
            CompiledUtils.AddDependency(root, module);
            var output = module.StringifyContent().Unwrap();
            var metadata = module.GetPowerShellObject().Unwrap().ToString();

            Assert.Multiple(() => {
                Assert.That(metadata, Does.Contain("Compression = 'None'"));
                Assert.That(metadata, Does.Contain("Type = 'UTF8String'"));
                Assert.That(output, Does.Contain("Invoke-PlainLocal"));
                Assert.That(output, Does.Contain("local plain payload"));
                Assert.That(output, Does.Not.Match("^[\"'][A-Za-z0-9+/=]+[\"']$"));
            });
        } finally {
            CompilerSettings.ConfigureEmbeddedLocalTextCompression("gzip");
        }
    }

    [Test, NonParallelizable]
    public void StringifyContent_BenchmarkSummaryReportsSavingsForGzipAndNone() {
        try {
            var gzipModule = TestData.CreateModule<CompiledLocalModule>($"function Invoke-GzipSummary {{ '{new string('a', 2048)}' }}", "GzipSummaryModule");
            var gzipRaw = gzipModule.GetContentBytes().Unwrap();
            var gzipPayload = gzipModule.GetEmbeddedPayloadBytes().Unwrap();

            CompilerSettings.ConfigureEmbeddedLocalTextCompression("none");
            var noneModule = TestData.CreateModule<CompiledLocalModule>("function Invoke-NoneSummary { 'none summary payload' }", "NoneSummaryModule");
            var noneRaw = noneModule.GetContentBytes().Unwrap();
            var nonePayload = noneModule.GetEmbeddedPayloadBytes().Unwrap();

            Assert.Multiple(() => {
                Assert.That(gzipPayload, Has.Length.LessThan(gzipRaw.Length));
                Assert.That(gzipRaw.Length - gzipPayload.Length, Is.GreaterThan(0));
                Assert.That((gzipRaw.Length - gzipPayload.Length) * 100.0 / gzipRaw.Length, Is.GreaterThan(0));
                Assert.That(nonePayload, Has.Length.EqualTo(noneRaw.Length));
                Assert.That(noneRaw.Length - nonePayload.Length, Is.EqualTo(0));
                Assert.That((noneRaw.Length - nonePayload.Length) * 100.0 / noneRaw.Length, Is.EqualTo(0));
            });
        } finally {
            CompilerSettings.ConfigureEmbeddedLocalTextCompression("gzip");
        }
    }

    [Test]
    public async Task StringifyContent_RemotePayloadKeepsNoCompressionMetadata() {
        var module = await CompiledRemoteModuleTests.TestData.GetTestRemoteModule();
        var output = module.StringifyContent().Unwrap();
        var bytes = Convert.FromBase64String(StripQuotedBase64(output));

        Assert.Multiple(() => {
            Assert.That(bytes, Is.Not.Empty);
            using var zipArchive = new ZipArchive(new MemoryStream(bytes), ZipArchiveMode.Read, false);
            Assert.That(zipArchive.Entries, Is.Not.Empty);
        });
    }

    [Test]
    public async Task GetPowerShellObject_RemotePayloadUsesNoneCompressionMetadata() {
        var module = await CompiledRemoteModuleTests.TestData.GetTestRemoteModule();
        var output = module.GetPowerShellObject().Unwrap().ToString();

        Assert.Multiple(() => {
            Assert.That(output, Does.Contain("Compression = 'None'"));
            Assert.That(output, Does.Contain("Type = 'Zip'"));
        });
    }

    private static string DecompressGzip(byte[] bytes) {
        using var input = new MemoryStream(bytes);
        using var gzip = new GZipStream(input, CompressionMode.Decompress);
        using var reader = new StreamReader(gzip, Encoding.UTF8, true);
        return reader.ReadToEnd();
    }

    [GeneratedRegex("^[\"'](?<content>[A-Za-z0-9+/=]+)[\"']$", RegexOptions.Singleline)]
    private static partial Regex Base64ContentRegex();

    private static string StripQuotedBase64(string payload) {
        var match = Base64ContentRegex().Match(payload);
        return match.Success ? match.Groups["content"].Value : payload;
    }

    public static class TestData {
        private static (PathedModuleSpec, CompiledDocument, RequirementGroup) PrepareRandomModule(string? contents = null, string? fileNameNoExt = null) {
            var random = TestContext.CurrentContext.Random;
            contents ??= $"""Write-Host "Hello, {random.GetString(10)}!";""";
            var document = CompiledDocument.FromBuilder(new TextEditor(new TextDocument(contents.Split('\n')))).Unwrap();
            var modulePath = Path.Combine(TestContext.CurrentContext.WorkDirectory, $"{fileNameNoExt ?? random.GetString(6)}.psm1");
            File.Create(modulePath).Close();
            var moduleSpec = new PathedModuleSpec(TestContext.CurrentContext.WorkDirectory, modulePath);

            return (moduleSpec, document, new RequirementGroup());

        }

        public static T CreateModule<T>(string? contents = null, string? fileNameNoExt = null) where T : RealCompiled {
            var (moduleSpec, document, requirementGroup) = PrepareRandomModule(contents, fileNameNoExt);
            return new Mock<T>(moduleSpec, document, requirementGroup) {
                CallBase = true
            }.Object;
        }

        public static async Task<RealCompiled> GetRandomCompiledModule(CompiledLocalModule? parent = null, int depLevel = 0, bool createDependencies = true) {
            var random = TestContext.CurrentContext.Random;
            createDependencies = !createDependencies && depLevel < 3 && random.NextBool();
            var scriptParent = parent as CompiledScript ?? parent?.GetRootParent();

            var createLocalModule = parent is null || random.NextBool();
            if (createLocalModule) {
                // Gotta create a script module
                if (depLevel == 0 || scriptParent is null) {
                    var compiledScript = CreateModule<CompiledScript>();

                    if (createDependencies) {
                        for (var i = 0; i < random.Next(1, 5); i++) {
                            var dependency = await GetRandomCompiledModule(compiledScript, depLevel + 1, createDependencies);
                            CompiledUtils.AddDependency(compiledScript, dependency);
                        }
                    }

                    return compiledScript;
                } else {
                    var module = CreateModule<CompiledLocalModule>();
                    CompiledUtils.AddDependency(scriptParent, module);

                    if (createDependencies) {
                        for (var i = 0; i < random.Next(1, 5); i++) {
                            var dependency = await GetRandomCompiledModule(module, depLevel + 1, createDependencies);
                            CompiledUtils.AddDependency(module, dependency);
                        }
                    }

                    return module;
                }
            } else {
                var remoteModule = await CompiledRemoteModuleTests.TestData.GetTestRemoteModule();
                CompiledUtils.AddDependency(scriptParent!, remoteModule);

                return remoteModule;
            }
        }
    }
}
