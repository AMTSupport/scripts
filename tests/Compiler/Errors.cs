using Compiler;
using Compiler.Analyser;
using Compiler.Requirements;
using LanguageExt;
using LanguageExt.Common;

namespace Compiler.Test;

[TestFixture]
public class ErrorsTests {
    [Test]
    public void InvalidModulePathError_FactoriesReturnMessages() {
        var notFile = InvalidModulePathError.NotAFile("/tmp/file.psm1");
        var notDirectory = InvalidModulePathError.ParentNotADirectory("/tmp");
        var notAbsolute = InvalidModulePathError.NotAnAbsolutePath("relative/path");

        Assert.Multiple(() => {
            Assert.That(notFile.Message, Does.Contain("must be a file"));
            Assert.That(notDirectory.Message, Does.Contain("must be a directory"));
            Assert.That(notAbsolute.Message, Does.Contain("absolute path"));
        });
    }

    [Test]
    public void EnrichableError_AppendsModuleName() {
        var module = new ModuleSpec("ModuleA");
        var error = (Error)Error.New("Base error");
        var wrapped = new WrappedErrorWithDebuggableContent("Wrapped", "content", error);

        var enriched = wrapped.Enrich(module);

        Assert.Multiple(() => {
            Assert.That(enriched.Message, Does.Contain("in module ModuleA"));
            Assert.That(enriched.Module.IsSome, Is.True);
            Assert.That(enriched.Inner.Unwrap().Message, Is.EqualTo("Base error"));
        });
    }

    [Test]
    public void EnrichableExceptional_AppendsModuleName() {
        var module = new ModuleSpec("ModuleB");
        var error = InvalidModulePathError.NotAFile("/tmp/file.psm1");
        var enriched = error.Enrich(module);

        Assert.Multiple(() => {
            Assert.That(enriched.Message, Does.Contain("in module ModuleB"));
            Assert.That(enriched.Module.IsSome, Is.True);
        });
    }

    [Test]
    public void ErrorUtils_EnrichesManyErrors() {
        var module = new ModuleSpec("ModuleC");
        var ast = AstHelper.GetAstReportingErrors("unknown-function", Option<string>.None, [], out _).Unwrap();
        var issue = Issue.Warning("Warning", ast.Extent, ast);
        var many = Error.Many(issue, Error.New("Other"));

        var enriched = many.Enrich(module);
        var expanded = enriched.ToString();

        Assert.That(expanded, Does.Contain("ModuleC"));
    }

    [Test]
    public void EnrichedException_EqualsAndMessageIncludesModule() {
        var module = new ModuleSpec("ModuleD");
        var exception = new InvalidOperationException("Boom");
        var enriched = new EnrichedException(exception, module);
        var same = new EnrichedException(exception, module);
        var isEqual = enriched.Equals(same);

        Assert.Multiple(() => {
            Assert.That(enriched.Message, Does.Contain("in module ModuleD"));
            Assert.That(isEqual, Is.True);
            Assert.That(enriched.GetHashCode(), Is.EqualTo(same.GetHashCode()));
        });
    }
}
