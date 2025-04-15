// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using Compiler.Requirements;
using System.Collections;
using Moq;
using RealCompiled = Compiler.Module.Compiled.Compiled;
using Compiler.Module.Compiled;
using QuikGraph;

namespace Compiler.Test.Module.Compiled;

[TestFixture]
public class CompiledTests {
    [TestCaseSource(typeof(TestData), nameof(TestData.AddRequirementHashData)), Repeat(10), Parallelizable]
    public void AddRequirementHashBytes_AlwaysSameResult(
        byte[] hashableBytes,
        RequirementGroup requirementGroup
    ) {
        var module = TestData.GetMockCompiledModule(hashableBytes);
        var random = TestContext.CurrentContext.Random;
        List<byte> bytesList;
        var hashResults = new List<byte[]>();
        do {
            bytesList = new List<byte>(hashableBytes);
            module.Object.AddRequirementHashBytes(bytesList, requirementGroup);
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
    public void GetRootParent_WhenNoParents_ReturnsNull() {
        var mockCompiled = TestData.GetMockCompiledModule();
        mockCompiled.Setup(x => x.Parents).Returns([]);

        Assert.That(mockCompiled.Object.GetRootParent(), Is.Null);
    }

    [Test]
    public void GetRootParent_WhenHasParents_ReturnsRootParent() {
        var rootParent = CompiledLocalModuleTests.TestData.CreateModule<CompiledScript>();
        var parent = TestData.GetMockCompiledModule();
        var mockCompiled = TestData.GetMockCompiledModule();
        mockCompiled.Setup(x => x.Parents).Returns([parent.Object]);
        parent.Setup(x => x.Parents).Returns([rootParent]);

        Assert.That(mockCompiled.Object.GetRootParent(), Is.EqualTo(rootParent));
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

    public static Mock<RealCompiled> GetMockCompiledModule(byte[]? bytes = null, CompiledScript? parent = null) {
        parent ??= CompiledLocalModuleTests.TestData.CreateModule<CompiledScript>();

        var random = TestContext.CurrentContext.Random;
        var moduleSpec = new ModuleSpec(random.GetString(6));
        var requirements = new RequirementGroup();
        if (bytes is null) {
            bytes = new byte[random.Next(10, 100)];
            random.NextBytes(bytes);
        }

        var mock = new Mock<RealCompiled>(moduleSpec, requirements, new Lazy<byte[]>(bytes)) {
            CallBase = true
        };
        CompiledUtils.AddDependency(parent, mock.Object);

        return mock;
    }
}

public static class CompiledUtils {
    public static void AddDependency(RealCompiled parent, RealCompiled dependency) {
        var rootParent = parent.GetRootParent()!;

        dependency.Parents.Add(parent);
        parent.Requirements.AddRequirement(dependency.ModuleSpec);
        rootParent.Graph.AddVerticesAndEdge(new Edge<RealCompiled>(rootParent, dependency));
    }

    public static void RemoveDependency(RealCompiled parent, RealCompiled dependency) {
        var rootParent = parent.GetRootParent()!;

        dependency.Parents.Remove(parent);
        parent.Requirements.RemoveRequirement(dependency.ModuleSpec);
        rootParent.Graph.RemoveEdge(new Edge<RealCompiled>(rootParent, dependency));
    }
}
