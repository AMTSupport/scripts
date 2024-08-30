// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using Compiler.Text;

namespace Compiler.Test.Text.Updater;

[TestFixture]
public sealed class ExactTests {
    private static readonly string[] LINES = """
    $string = @"
    Hello,
    World!
    I'm the
    Document!
    "@;
    """.Split('\n');

    private TextEditor Editor;

    [SetUp]
    public void SetUp() => this.Editor = new TextEditor(new(LINES));

    [TestCaseSource(typeof(ExactTests), nameof(ReplaceContentWithUpdateCases))]
    public string AddExactEdit_ReplaceContentWithEmpty(
        int startingIndex,
        int startingColumn,
        int endingIndex,
        int endingColumn,
        UpdateOptions options,
        Func<string[], string[]> content
    ) {
        this.Editor.AddExactEdit(startingIndex, startingColumn, endingIndex, endingColumn, options, content);
        var compiled = CompiledDocument.FromBuilder(this.Editor).ThrowIfFail();

        return compiled.GetContent();
    }

    public static IEnumerable ReplaceContentWithUpdateCases {
        get {
            yield return new TestCaseData(1, 0, 4, 9, UpdateOptions.None, (Func<string[], string[]>)(_ => []))
                .Returns("""
                $string = @"
                "@;
                """).SetName("Replace all multiline-content with empty");

            yield return new TestCaseData(1, 0, 4, 9, UpdateOptions.None, (Func<string[], string[]>)(_ => []))
                .Returns("""
                $string = @"
                "@;
                """).SetName("Replace all content with empty except first and last line");

            yield return new TestCaseData(1, 0, 4, 9, UpdateOptions.None, (Func<string[], string[]>)(content => {
                return content.Select(line => line + " Updated content!").ToArray();
            })).Returns("""
            $string = @"
            Hello, Updated content!
            World! Updated content!
            I'm the Updated content!
            Document! Updated content!
            "@;
            """).SetName("Append 'Updated content!' to middle lines");

            yield return new TestCaseData(0, 0, 0, 8, UpdateOptions.InsertInline, (Func<string[], string[]>)(content => {
                return content.Select(line => line.Replace("string", "epicString")).ToArray();
            })).Returns("""
            $epicString = @"
            Hello,
            World!
            I'm the
            Document!
            "@;
            """).SetName("Update variable name in first line.");

            yield return new TestCaseData(5, 2, 5, 3, UpdateOptions.InsertInline, (Func<string[], string[]>)(content => {
                return [];
            })).Returns("""
            $string = @"
            Hello,
            World!
            I'm the
            Document!
            "@
            """).SetName("Remove semi-colon from last line.");

            yield return new TestCaseData(1, 0, 4, 9, UpdateOptions.None, (Func<string[], string[]>)(content => {
                return ["Updated content!"];
            })).Returns("""
            $string = @"
            Updated content!
            "@;
            """).SetName("Replace multiline content with 'Updated content!'");
        }
    }
}
