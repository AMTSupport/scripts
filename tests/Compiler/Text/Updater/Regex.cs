// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Text.RegularExpressions;
using Compiler.Text;

namespace Compiler.Test.Text.Updater;

[TestFixture]
public sealed class RegexTests {
    public static readonly string[] LINES = """
    $string = @"
    Hello,
    World!
    I'm the
    Document!
    "@;
    """.Split('\n');

    [TestCaseSource(typeof(TestData), nameof(TestData.AddRegexEditCases))]
    public string AddRegexEdit(
        string pattern,
        UpdateOptions options,
        Func<Match, string> updater
    ) {
        var editor = new TextEditor(new(LINES));

        editor.AddRegexEdit(new Regex(pattern), options, updater);
        var compiled = CompiledDocument.FromBuilder(editor).ThrowIfFail();

        return compiled.GetContent();
    }
}

file static class TestData {
    public static IEnumerable AddRegexEditCases {
        get {
            yield return new TestCaseData(
                ".+",
                UpdateOptions.MatchEntireDocument,
                (Func<Match, string>)(_ => string.Empty)
            ).Returns(string.Empty).SetName("Replace all content with empty string");

            yield return new TestCaseData(
                ".+",
                UpdateOptions.None,
                (Func<Match, string>)(_ => string.Empty)
            ).Returns(new string('\n', 5)).SetName("Replace each line with empty string");


            yield return new TestCaseData(
                ".+",
                UpdateOptions.MatchEntireDocument,
                (Func<Match, string>)(_ => "Updated Content")
            ).Returns("Updated Content").SetName("Replace all content with 'Updated Content'");

            yield return new TestCaseData(
                "^((?!@\"|\"@).)*$", // Match all lines not containing '@"' or '"@' (multiline string tokens)
                UpdateOptions.None,
                (Func<Match, string>)(m => m.Value + " Updated Content")
            ).Returns("""
            $string = @"
            Hello, Updated Content
            World! Updated Content
            I'm the Updated Content
            Document! Updated Content
            "@;
            """).SetName("Prepend 'Updated Content' to each line");
        }
    }
}
