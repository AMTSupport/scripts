// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Management.Automation.Language;
using Compiler.Text.Updater.Built;

namespace Compiler.Test.Text.Updater.Built;

public class HereStringUpdaterTests {
    [TestCaseSource(typeof(TestData), nameof(TestData.Data))]
    public string InternalApply_UpdatesHereStrings(string astContent) {
        var ast = AstHelper.GetAstReportingErrors(astContent, default, []).Unwrap().Find(ast => ast is StringConstantExpressionAst, false)!;
        var result = HereStringUpdater.InternalApply(ast);

        Assert.That(result, Is.Not.Null.Or.Empty);
        return string.Join('\n', result);
    }

    private static class TestData {
        public static IEnumerable Data {
            get {
                yield return new TestCaseData("""
                @'
                Here-string
                '@
                """).Returns("""
                @"
                Here-string
                "@
                """);

                yield return new TestCaseData("""
                @"
                Here-string
                "@
                """).Returns("""
                @"
                Here-string
                "@
                """);

                yield return new TestCaseData("""
                @"
                @'
                what looks like a nested here-string but isn't!
                '@
                "@
                """).Returns("""
                @"
                @'
                what looks like a nested here-string but isn't!
                '@
                "@
                """);
            }
        }
    }
}
