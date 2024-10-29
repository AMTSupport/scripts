// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using static Compiler.Module.Compiled.Compiled;
using Compiler.Requirements;
using System.Collections;
using Moq;
using RealCompiled = Compiler.Module.Compiled.Compiled;

namespace Compiler.Test.Module.Compiled;

[TestFixture]
public class CompiledTests {
    [TestCaseSource(typeof(TestData), nameof(TestData.AddRequirementHashData)), Repeat(10), Parallelizable]
    public void AddRequirementHashBytes_AlwaysSameResult(
        byte[] hashableBytes,
        RequirementGroup requirementGroup
    ) {
        var random = TestContext.CurrentContext.Random;
        List<byte> bytesList;
        var hashResults = new List<byte[]>();
        do {
            bytesList = new List<byte>(hashableBytes);
            AddRequirementHashBytes(bytesList, requirementGroup);
            hashResults.Add([.. hashableBytes]);
        } while (hashResults.Count < random.Next(2, 5));

        var firstResult = hashResults.First();
        Assert.Multiple(() => {
            foreach (var result in hashResults) {
                Assert.That(result, Is.EqualTo(firstResult));
            }
        });
    }

    [Test]
    public void GetRootParent_WhenNoParents_ReturnsSelf() {
        var mockCompiled = TestData.GetMockCompiledModule();
        mockCompiled.Setup(x => x.Parents).Returns([]);

        Assert.That(mockCompiled.Object.GetRootParent(), Is.EqualTo(mockCompiled.Object));
    }

    [Test]
    public void GetRootParent_WhenHasParents_ReturnsRootParent() {
        var rootParent = TestData.GetMockCompiledModule();
        var parent = TestData.GetMockCompiledModule();
        var mockCompiled = TestData.GetMockCompiledModule();
        mockCompiled.Setup(x => x.Parents).Returns([parent.Object]);
        parent.Setup(x => x.Parents).Returns([rootParent.Object]);

        Assert.That(mockCompiled.Object.GetRootParent(), Is.EqualTo(rootParent.Object));
    }
}

file static class TestData {
    public static IEnumerable AddRequirementHashData {
        get {
            var random = TestContext.CurrentContext.Random;
            var hashableBytes = new byte[random.Next(10, 100)];
            random.NextBytes(hashableBytes);

            var sourceRoot = Path.Combine(TestUtils.RepositoryDirectory(), "src");
            var environmentPath = Path.Combine(sourceRoot, "common/Environment.psm1");

            yield return new TestCaseData(
                hashableBytes,
                new RequirementGroup() {
                    StoredRequirements = {
                        { typeof(ModuleSpec), new HashSet<Requirement> {
                            new ModuleSpec("PSWindowsUpdate"),
                            new ModuleSpec("PSReadLine", requiredVersion: new (2, 3, 5)),
                            new PathedModuleSpec(sourceRoot, environmentPath)
                        } },
                        { typeof(PSEditionRequirement), new HashSet<Requirement> {
                            new PSEditionRequirement(PSEdition.Core)
                        } },
                        { typeof(UsingNamespace), new HashSet<Requirement> {
                            new UsingNamespace("System.Collections"),
                            new UsingNamespace("System.Diagnostics")
                        } },
                    }
                }
            ).SetName("Multiple types of Requirements");

            yield return new TestCaseData(
                hashableBytes,
                new RequirementGroup() {
                    StoredRequirements = {
                        { typeof(ModuleSpec), new HashSet<Requirement> {
                            new PathedModuleSpec(sourceRoot, environmentPath)
                        } },
                    }
                }
            ).SetName("Single type of Requirement");
        }
    }

    public static Mock<RealCompiled> GetMockCompiledModule() {
        var random = TestContext.CurrentContext.Random;
        var moduleSpec = new ModuleSpec(random.GetString(6));
        var requirements = new RequirementGroup();
        var hashableBytes = new byte[random.Next(10, 100)];
        random.NextBytes(hashableBytes);

        return new Mock<RealCompiled>(moduleSpec, requirements, hashableBytes) {
            CallBase = true
        };
    }
}
