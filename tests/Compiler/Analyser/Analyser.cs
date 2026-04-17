using Compiler.Analyser;
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
}
