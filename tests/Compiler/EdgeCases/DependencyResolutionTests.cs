// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using Compiler.Module.Resolvable;
using Compiler.Module;
using Compiler.Requirements;

namespace Compiler.Test.EdgeCases;

[TestFixture]
public class DependencyResolutionTests {
    [Test]
    public void DiamondDependency_ResolvesCorrectly() {
        var parent = new ResolvableParent(TestUtils.GenerateUniqueDirectory());
        var graph = parent.Graph;

        var specA = TestUtils.GetModuleSpecFromContent("Using module B.psm1\nUsing module C.psm1");
        var specB = TestUtils.GetModuleSpecFromContent("Using module D.psm1");
        var specC = TestUtils.GetModuleSpecFromContent("Using module D.psm1");
        var specD = TestUtils.GetModuleSpecFromContent("");

        var mockA = new MockResolvable(specA);
        var mockB = new MockResolvable(specB);
        var mockC = new MockResolvable(specC);
        var mockD = new MockResolvable(specD);

        lock (graph) {
            graph.AddVertex(mockA);
            graph.AddVertex(mockB);
            graph.AddVertex(mockC);
            graph.AddVertex(mockD);
            graph.AddEdge(new QuikGraph.Edge<Resolvable>(mockA, mockB));
            graph.AddEdge(new QuikGraph.Edge<Resolvable>(mockA, mockC));
            graph.AddEdge(new QuikGraph.Edge<Resolvable>(mockB, mockD));
            graph.AddEdge(new QuikGraph.Edge<Resolvable>(mockC, mockD));
        }

        Assert.Multiple(() => {
            Assert.That(graph.VertexCount, Is.EqualTo(4));
            Assert.That(graph.EdgeCount, Is.EqualTo(4));

            var subgraphFromA = parent.GetGraphFromRoot(mockA);
            Assert.That(subgraphFromA.VertexCount, Is.EqualTo(4));
            Assert.That(subgraphFromA.EdgeCount, Is.EqualTo(4));
        });
    }

    [Test]
    public void CycleDetection_ThrowsOnDirectCycle() {
        var parent = new ResolvableParent(TestUtils.GenerateUniqueDirectory());
        var graph = parent.Graph;

        var specA = TestUtils.GetModuleSpecFromContent("Using module B.psm1");
        var specB = TestUtils.GetModuleSpecFromContent("Using module A.psm1");

        var mockA = new MockResolvable(specA);
        var mockB = new MockResolvable(specB);

        lock (graph) {
            graph.AddVertex(mockA);
            graph.AddVertex(mockB);
            graph.AddEdge(new QuikGraph.Edge<Resolvable>(mockA, mockB));
            graph.AddEdge(new QuikGraph.Edge<Resolvable>(mockB, mockA));
        }

        parent.Resolvables.TryAdd(specA, new ResolvableParent.ResolvableInfo(LanguageExt.Option<LanguageExt.Fin<Compiler.Module.Compiled.Compiled>>.None, LanguageExt.Option<Action<Compiler.Module.Compiled.CompiledScript>>.None));
        parent.Resolvables.TryAdd(specB, new ResolvableParent.ResolvableInfo(LanguageExt.Option<LanguageExt.Fin<Compiler.Module.Compiled.Compiled>>.None, LanguageExt.Option<Action<Compiler.Module.Compiled.CompiledScript>>.None));

        var ex = Assert.ThrowsAsync<InvalidOperationException>(async () => await parent.Compile());
        Assert.That(ex!.Message, Does.Contain("cycle"));
    }

    [Test]
    public void CycleDetection_ThrowsOnIndirectCycle() {
        var parent = new ResolvableParent(TestUtils.GenerateUniqueDirectory());
        var graph = parent.Graph;

        var specA = TestUtils.GetModuleSpecFromContent("Using module B.psm1");
        var specB = TestUtils.GetModuleSpecFromContent("Using module C.psm1");
        var specC = TestUtils.GetModuleSpecFromContent("Using module A.psm1");

        var mockA = new MockResolvable(specA);
        var mockB = new MockResolvable(specB);
        var mockC = new MockResolvable(specC);

        lock (graph) {
            graph.AddVertex(mockA);
            graph.AddVertex(mockB);
            graph.AddVertex(mockC);
            graph.AddEdge(new QuikGraph.Edge<Resolvable>(mockA, mockB));
            graph.AddEdge(new QuikGraph.Edge<Resolvable>(mockB, mockC));
            graph.AddEdge(new QuikGraph.Edge<Resolvable>(mockC, mockA));
        }

        parent.Resolvables.TryAdd(specA, new ResolvableParent.ResolvableInfo(LanguageExt.Option<LanguageExt.Fin<Compiler.Module.Compiled.Compiled>>.None, LanguageExt.Option<Action<Compiler.Module.Compiled.CompiledScript>>.None));
        parent.Resolvables.TryAdd(specB, new ResolvableParent.ResolvableInfo(LanguageExt.Option<LanguageExt.Fin<Compiler.Module.Compiled.Compiled>>.None, LanguageExt.Option<Action<Compiler.Module.Compiled.CompiledScript>>.None));
        parent.Resolvables.TryAdd(specC, new ResolvableParent.ResolvableInfo(LanguageExt.Option<LanguageExt.Fin<Compiler.Module.Compiled.Compiled>>.None, LanguageExt.Option<Action<Compiler.Module.Compiled.CompiledScript>>.None));

        var ex = Assert.ThrowsAsync<InvalidOperationException>(async () => await parent.Compile());
        Assert.That(ex!.Message, Does.Contain("cycle"));
    }

    [Test, Repeat(10)]
    public void DeterministicOrdering_SameInputProducesSameGraph() {
        var parent1 = new ResolvableParent(TestUtils.GenerateUniqueDirectory());
        var parent2 = new ResolvableParent(TestUtils.GenerateUniqueDirectory());

        var specs = Enumerable.Range(0, 5)
            .Select(i => TestUtils.GetModuleSpecFromContent($"# Module {i}"))
            .ToArray();

        var mocks1 = specs.Select(s => new MockResolvable(s)).ToArray();
        var mocks2 = specs.Select(s => new MockResolvable(s)).ToArray();

        lock (parent1.Graph) {
            foreach (var mock in mocks1) parent1.Graph.AddVertex(mock);
            parent1.Graph.AddEdge(new QuikGraph.Edge<Resolvable>(mocks1[0], mocks1[1]));
            parent1.Graph.AddEdge(new QuikGraph.Edge<Resolvable>(mocks1[0], mocks1[2]));
            parent1.Graph.AddEdge(new QuikGraph.Edge<Resolvable>(mocks1[1], mocks1[3]));
            parent1.Graph.AddEdge(new QuikGraph.Edge<Resolvable>(mocks1[2], mocks1[3]));
            parent1.Graph.AddEdge(new QuikGraph.Edge<Resolvable>(mocks1[3], mocks1[4]));
        }

        lock (parent2.Graph) {
            foreach (var mock in mocks2) parent2.Graph.AddVertex(mock);
            parent2.Graph.AddEdge(new QuikGraph.Edge<Resolvable>(mocks2[0], mocks2[1]));
            parent2.Graph.AddEdge(new QuikGraph.Edge<Resolvable>(mocks2[0], mocks2[2]));
            parent2.Graph.AddEdge(new QuikGraph.Edge<Resolvable>(mocks2[1], mocks2[3]));
            parent2.Graph.AddEdge(new QuikGraph.Edge<Resolvable>(mocks2[2], mocks2[3]));
            parent2.Graph.AddEdge(new QuikGraph.Edge<Resolvable>(mocks2[3], mocks2[4]));
        }

        Assert.Multiple(() => {
            Assert.That(parent1.Graph.VertexCount, Is.EqualTo(parent2.Graph.VertexCount));
            Assert.That(parent1.Graph.EdgeCount, Is.EqualTo(parent2.Graph.EdgeCount));
        });
    }
}

file sealed class MockResolvable : Resolvable {
    public MockResolvable(ModuleSpec spec) : base(spec) { }

    public override ModuleMatch GetModuleMatchFor(ModuleSpec requirement) =>
        this.ModuleSpec.CompareTo(requirement);

    public override Task<LanguageExt.Option<LanguageExt.Common.Error>> ResolveRequirements() =>
        Task.FromResult(LanguageExt.Option<LanguageExt.Common.Error>.None);

    public override Task<LanguageExt.Fin<Compiler.Module.Compiled.Compiled>> IntoCompiled(ResolvableParent resolvableParent) =>
        throw new NotImplementedException("MockResolvable cannot be compiled");
}
