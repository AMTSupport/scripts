// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation.Language;
using Compiler.Analyser;
using Compiler.Analyser.Rules;
using LanguageExt;

namespace Compiler.Test.Analyser.Rules;

[TestFixture]
public class UseOfUnknownFunctionTests {
    [Test]
    public void BuiltInFunction_DoesNotCreateIssue() {
        var visitor = new RuleVisitor([new UseOfUndefinedFunction()], []);
        var ast = AstHelper.GetAstReportingErrors("Write-Host 'Hello'", Option<string>.None, [], out _).Unwrap();
        ast.Visit(visitor);

        Assert.That(visitor.Issues, Is.Empty);
    }

    [Test]
    public void LocalFunction_DoesNotCreateIssue() {
        var script = """
        function Test-Function { }
        Test-Function
        """;
        var visitor = new RuleVisitor([new UseOfUndefinedFunction()], []);
        var ast = AstHelper.GetAstReportingErrors(script, Option<string>.None, [], out _).Unwrap();
        ast.Visit(visitor);

        Assert.That(visitor.Issues, Is.Empty);
    }

    [Test]
    public void Alias_DoesNotCreateIssue() {
        var script = """
        function Real-Thing { }
        Set-Alias -Name Alias-Thing -Value Real-Thing
        Alias-Thing
        """;
        var visitor = new RuleVisitor([new UseOfUndefinedFunction()], []);
        var ast = AstHelper.GetAstReportingErrors(script, Option<string>.None, [], out _).Unwrap();
        ast.Visit(visitor);

        Assert.That(visitor.Issues, Is.Empty);
    }

    [Test]
    public void UnknownFunction_CreatesWarning() {
        var visitor = new RuleVisitor([new UseOfUndefinedFunction()], []);
        var ast = AstHelper.GetAstReportingErrors("unknown-function", Option<string>.None, [], out _).Unwrap();
        ast.Visit(visitor);

        Assert.Multiple(() => {
            Assert.That(visitor.Issues, Has.Count.EqualTo(1));
            Assert.That(visitor.Issues[0].Severity, Is.EqualTo(IssueSeverity.Warning));
            Assert.That(visitor.Issues[0].Message, Does.Contain("Undefined function"));
        });
    }

    [Test]
    public void SuppressionAttribute_SkipsWarning() {
        var script = """
        function Test-Function {
            [SuppressAnalyser('UseOfUndefinedFunction', 'unknown-function', 'Justification')]
            param()
            unknown-function
        }
        Test-Function
        """;
        var visitor = new RuleVisitor([new UseOfUndefinedFunction()], []);
        var ast = AstHelper.GetAstReportingErrors(script, Option<string>.None, [], out _).Unwrap();
        ast.Visit(visitor);

        Assert.That(visitor.Issues, Is.Empty);
    }

    [Test]
    public void SuppressionList_SkipsWarning() {
        var script = "unknown-function";
        var ast = AstHelper.GetAstReportingErrors(script, Option<string>.None, [], out _).Unwrap();
        var command = ast.Find(static node => node is CommandAst, true) as CommandAst;
        var rule = new UseOfUndefinedFunction();
        var suppressions = new[] {
            new Suppression(typeof(UseOfUndefinedFunction), new List<string> { "unknown-function", "other" }, "Justification")
        };

        Assert.Multiple(() => {
            Assert.That(command, Is.Not.Null);
            Assert.That(rule.ShouldProcess(command!, suppressions), Is.False);
        });
    }
}
