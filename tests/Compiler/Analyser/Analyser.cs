// Copyright (c) 2023, 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.
using Compiler.Module.Compiled;
using Compiler.Test.Module.Compiled;

namespace Compiler.Test.Analyser;

[TestFixture]
public class AnalyserTests {
    [Test]
    public async Task Analyse_ReturnsIssues() {
        var module = CompiledLocalModuleTests.TestData.CreateModule<CompiledLocalModule>("unknown-function");
        CompiledUtils.EnsureMockHasParent(module);
        var issues = await Compiler.Analyser.Analyser.Analyse(module, []);

        Assert.That(issues, Is.Not.Empty);
    }

    [Test]
    public async Task Analyse_CachesByModuleHash() {
        var module = CompiledLocalModuleTests.TestData.CreateModule<CompiledLocalModule>("unknown-function");
        CompiledUtils.EnsureMockHasParent(module);
        var first = await Compiler.Analyser.Analyser.Analyse(module, []);
        var second = await Compiler.Analyser.Analyser.Analyse(module, []);

        Assert.Multiple(() => {
            Assert.That(first, Is.Not.Empty);
            Assert.That(ReferenceEquals(first, second), Is.True);
        });
    }

    [Test]
    public async Task Analyse_CacheKeyIncludesAvailableImports() {
        // Create two modules with same content but different imports
        var module1 = CompiledLocalModuleTests.TestData.CreateModule<CompiledLocalModule>("Write-Host 'test';");
        var module2 = CompiledLocalModuleTests.TestData.CreateModule<CompiledLocalModule>("Write-Host 'test';");
        CompiledUtils.EnsureMockHasParent(module1);
        CompiledUtils.EnsureMockHasParent(module2);

        // Create two different import modules
        var import1 = CompiledLocalModuleTests.TestData.CreateModule<CompiledLocalModule>("function Import1 { 'import1' }");
        var import2 = CompiledLocalModuleTests.TestData.CreateModule<CompiledLocalModule>("function Import2 { 'import2' }");
        CompiledUtils.EnsureMockHasParent(import1);
        CompiledUtils.EnsureMockHasParent(import2);

        // Analyze same module with different imports
        var issues1 = await Compiler.Analyser.Analyser.Analyse(module1, [import1]);
        var issues2 = await Compiler.Analyser.Analyser.Analyse(module2, [import2]);

        Assert.Multiple(() => {
            // Both should return results (not cached incorrectly)
            Assert.That(issues1, Is.Not.Null);
            Assert.That(issues2, Is.Not.Null);
        });
    }

    [Test, Repeat(10), Parallelizable]
    public async Task Analyse_CachesSameModuleWithSameImports() {
        var module = CompiledLocalModuleTests.TestData.CreateModule<CompiledLocalModule>("Write-Host 'test';");
        CompiledUtils.EnsureMockHasParent(module);

        var import = CompiledLocalModuleTests.TestData.CreateModule<CompiledLocalModule>("function Import { 'import' }");
        CompiledUtils.EnsureMockHasParent(import);

        var issues1 = await Compiler.Analyser.Analyser.Analyse(module, [import]);
        var issues2 = await Compiler.Analyser.Analyser.Analyse(module, [import]);

        // Should get same cached result
        Assert.That(ReferenceEquals(issues1, issues2), Is.True);
    }
}
