// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Text.RegularExpressions;
using Compiler.Module.Resolvable;
using Compiler.Text;

namespace Compiler.Test.Text.Updater;

[TestFixture]
public class PatternTests {
    [TestCaseSource(typeof(TestData), nameof(TestData.AddPatternEditCases))]
    public string AddPatternEdit(
        string[] testLines,
        string openingPattern,
        string closingPattern,
        UpdateOptions options,
        Func<string[], string[]> updater
    ) {
        var editor = new TextEditor(new(testLines));

        editor.AddPatternEdit(new Regex(openingPattern), new Regex(closingPattern), options, updater);
        var compiled = CompiledDocument.FromBuilder(editor).ThrowIfFail();

        return compiled.GetContent();
    }

    public static class TestData {
        private static readonly string[] DOCUMENTATION_LINES = /*ps1*/ """
        <#
        .DESCRIPTION
            This module contains utility functions that have no dependencies on other modules and can be used by any module.
        #>

        <#
        .DESCRIPTION
            This function is used to measure the time it takes to execute a script block.

        .EXAMPLE
            Measure-ElapsedTime {
                Start-Sleep -Seconds 5;
            }
        #>
        """.Split('\n');

        public static IEnumerable AddPatternEditCases {
            get {
                yield return new TestCaseData(
                    DOCUMENTATION_LINES,
                    ResolvableLocalModule.DocumentationStartRegex().ToString(),
                    ResolvableLocalModule.DocumentationEndRegex().ToString(),
                    UpdateOptions.None,
                    (Func<string[], string[]>)(_ => [])
                ).Returns(string.Empty).SetName("Ensure that documentation blocks are removed from content.");
            }

        }
    }
}
