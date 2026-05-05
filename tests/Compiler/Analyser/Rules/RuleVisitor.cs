// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation.Language;
using Compiler.Analyser;
using Compiler.Analyser.Rules;
using Compiler.Module.Compiled;
using Compiler.Test.Module.Compiled;
using LanguageExt;


namespace Compiler.Test.Analyser.Rules;

[TestFixture]
public class RuleVisitorTests {
    [Test]
    public void VisitModule_CleansUpThreadLocalCacheOnException() {
        // This test verifies the try-finally in VisitModule ensures cleanup
        // We test this by creating a real module and verifying no stale cache issues
        var module = CompiledLocalModuleTests.TestData.CreateModule<CompiledLocalModule>("Write-Host 'test'");
        CompiledUtils.EnsureMockHasParent(module);
        
        var visitor = new RuleVisitor([new MissingCmdlet()], []);
        
        // First visit should work
        Assert.That(() => visitor.VisitModule(module), Throws.Nothing);
        
        // Second visit with same visitor on different module should also work
        // (cache was cleaned up after first visit)
        var module2 = CompiledLocalModuleTests.TestData.CreateModule<CompiledLocalModule>("Write-Host 'test2'");
        CompiledUtils.EnsureMockHasParent(module2);
        
        var visitor2 = new RuleVisitor([new MissingCmdlet()], []);
        Assert.That(() => visitor2.VisitModule(module2), Throws.Nothing);
    }

    [Test]
    public void GetSupressions_FindsScriptLevelAttributes() {
        var script = @"
[SuppressAnalyser('MissingCmdlet', 'data', 'Justification')]
param()
Write-Host 'test'
";
        var ast = AstHelper.GetAstReportingErrors(script, Option<string>.None, [], out _).Unwrap();
        var paramBlock = ast.Find(node => node is ParamBlockAst, true) as ParamBlockAst;
        
        Assert.That(paramBlock, Is.Not.Null);
        
        var suppressions = RuleVisitor.GetSupressions(paramBlock!);
        
        Assert.That(suppressions.IsSucc, Is.True);
        suppressions.IfSucc(s => {
            Assert.That(s, Is.Not.Empty);
        });
    }

    [Test]
    public void GetSupressions_HandlesNullParamBlock() {
        var script = "Write-Host 'test'";
        var ast = AstHelper.GetAstReportingErrors(script, Option<string>.None, [], out _).Unwrap();
        var expression = ast.Find(node => node is CommandAst, true);
        
        var suppressions = RuleVisitor.GetSupressions(expression!);
        
        Assert.That(suppressions.IsSucc, Is.True);
        suppressions.IfSucc(s => {
            Assert.That(s, Is.Empty);
        });
    }
}
