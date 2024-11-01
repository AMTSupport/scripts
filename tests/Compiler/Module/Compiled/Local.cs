// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation.Language;
using Compiler.Module.Compiled;
using Compiler.Requirements;
using Compiler.Text;
using Moq;
using RealCompiled = Compiler.Module.Compiled.Compiled;

namespace Compiler.Test.Module.Compiled;

[TestFixture]
public class CompiledLocalModuleTests {
    [Test, Repeat(10), Parallelizable]
    public void StringifyContent_ReturnsValidAstContent() {
        var module = TestData.GetRandomCompiledModule();
        var stringifiedContent = module.StringifyContent();
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

        var expression = scriptOneHello == scriptTwoHello ? Is.EqualTo(scriptTwo.ComputedHash) : Is.Not.EqualTo(scriptTwo.ComputedHash);
        Assert.That(scriptOne.ComputedHash, expression, "Hashes should be the same if the content is the same.");

        if (scriptOneHello == scriptTwoHello) {
            var oldHash = scriptOne.ComputedHash;

            var remoteModule = CompiledRemoteModuleTests.TestData.GetTestRemoteModule();
            CompiledUtils.AddDependency(scriptOne, remoteModule);
            Assert.That(scriptOne.ComputedHash, Is.Not.EqualTo(oldHash), "Hash should change when a dependency is added.");
            Assert.That(scriptOne.ComputedHash, Is.Not.EqualTo(scriptTwo.ComputedHash), "Hashes should differ when a dependency is added.");

            CompiledUtils.AddDependency(scriptTwo, remoteModule);
            Assert.That(scriptOne.ComputedHash, Is.EqualTo(scriptTwo.ComputedHash), "Hashes should not differ when the dependencies are the same.");

            // Check that a nested dependency changes the hash of the top module
            var moduleContent = "Write-Host 'Hello, World!';";
            var randomName = TestContext.CurrentContext.Random.GetString(6);
            var moduleDependencyOne = TestData.CreateModule<CompiledLocalModule>(moduleContent, randomName);
            var moduleDependencyTwo = TestData.CreateModule<CompiledLocalModule>(moduleContent, randomName);
            var nestedDependencyOne = TestData.CreateModule<CompiledLocalModule>("Write-Host 'Hello, Nested World!';");

            CompiledUtils.AddDependency(scriptOne, moduleDependencyOne);
            CompiledUtils.AddDependency(scriptTwo, moduleDependencyTwo);
            CompiledUtils.AddDependency(moduleDependencyOne, nestedDependencyOne);
            CompiledUtils.AddDependency(moduleDependencyTwo, nestedDependencyOne);
            Assert.That(moduleDependencyOne.ComputedHash, Is.EqualTo(moduleDependencyTwo.ComputedHash), "Hashes should be the same if the dependencies are the same.");
            Assert.That(scriptOne.ComputedHash, Is.EqualTo(scriptTwo.ComputedHash), "Hashes should not differ when a nested dependency matches.");

            var nestedDependencyTwo = TestData.CreateModule<CompiledLocalModule>("Write-Host 'Hello, Other Nested World!';");
            CompiledUtils.RemoveDependency(moduleDependencyTwo, nestedDependencyOne);
            CompiledUtils.AddDependency(moduleDependencyTwo, nestedDependencyTwo);
            Assert.That(moduleDependencyOne.ComputedHash, Is.Not.EqualTo(moduleDependencyTwo.ComputedHash), "Hashes should differ when the dependency changes.");
            Assert.That(scriptOne.ComputedHash, Is.Not.EqualTo(scriptTwo.ComputedHash), "Hashes should differ when a nested dependency changes.");
        }
    });

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

        public static RealCompiled GetRandomCompiledModule(CompiledLocalModule? parent = null, int depLevel = 0, bool createDependencies = true) {
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
                            var dependency = GetRandomCompiledModule(compiledScript, depLevel + 1, createDependencies);
                            CompiledUtils.AddDependency(compiledScript, dependency);
                        }
                    }

                    return compiledScript;
                } else {
                    var module = CreateModule<CompiledLocalModule>();
                    CompiledUtils.AddDependency(scriptParent, module);

                    if (createDependencies) {
                        for (var i = 0; i < random.Next(1, 5); i++) {
                            var dependency = GetRandomCompiledModule(module, depLevel + 1, createDependencies);
                            CompiledUtils.AddDependency(module, dependency);
                        }
                    }

                    return module;
                }
            } else {
                var remoteModule = CompiledRemoteModuleTests.TestData.GetTestRemoteModule();
                CompiledUtils.AddDependency(scriptParent!, remoteModule);

                return remoteModule;
            }
        }
    }
}
