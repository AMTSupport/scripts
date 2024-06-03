using System.Collections;
using System.Diagnostics.CodeAnalysis;
using System.Text.RegularExpressions;
using Text;

namespace Compiler.Test.Text;

[TestFixture]
public class PatternTests
{
    private readonly string[] LINES = [
        "@\"",
        "Doing cool stuff with this multiline string!",
        "",
        "This is the end of the string!",
        "\"@"
    ];

    [TestCaseSource(typeof(TestData), nameof(TestData.AddPatternEditCases))]
    public string AddPatternEdit(
        [StringSyntax("Regex")] string openingPattern,
        [StringSyntax("Regex")] string closingPattern,
        UpdateOptions options,
        Func<string[], string[]> updater
    )
    {
        var editor = new TextEditor(new(LINES));

        editor.AddPatternEdit(new Regex(openingPattern), new Regex(closingPattern), options, updater);
        var compiled = CompiledDocument.FromBuilder(editor);

        return compiled.GetContent();
    }

    public static class TestData
    {
        public static IEnumerable AddPatternEditCases
        {
            get
            {
                yield return new TestCaseData("@\"", "\"@", UpdateOptions.None, (Func<string[], string[]>)(_ => [])).Returns(string.Empty).SetName("Replace all content with empty string");
                yield return new TestCaseData("@\"", "\"@", UpdateOptions.None, (Func<string[], string[]>)(_ => ["Updated content!"])).Returns("Updated content!").SetName("Replace all content with 'Updated content'");
                yield return new TestCaseData("@\"", "\"@", UpdateOptions.None, (Func<string[], string[]>)(content => content.Select((line, index) =>
                {
                    if (index > 0 && index < content.Length - 1)
                    {
                        return line + "Updated content!";
                    }
                    else
                    {
                        return line;
                    }
                }).ToArray())).Returns(string.Join('\n', [
                    "@\"",
                    "Doing cool stuff with this multiline string!Updated content!",
                    "Updated content!",
                    "This is the end of the string!Updated content!",
                    "\"@"
                ])).SetName("Prepend 'Updated content' to each line except first and last");
            }

        }
    }
}

[TestFixture]
public class RegexTests
{
    public static readonly string[] LINES = ["Hello,", "World!", "I'm the", "Document!"];

    [TestCaseSource(typeof(TestData), nameof(TestData.AddRegexEditCases))]
    public string AddRegexEdit(
        [StringSyntax("Regex")] string pattern,
        UpdateOptions options,
        Func<Match, string> updater
    )
    {
        var editor = new TextEditor(new(LINES));

        editor.AddRegexEdit(new Regex(pattern), options, updater);
        var compiled = CompiledDocument.FromBuilder(editor);

        return compiled.GetContent();
    }

    public static class TestData
    {
        public static IEnumerable AddRegexEditCases
        {
            get
            {
                yield return new TestCaseData(".+", UpdateOptions.MatchEntireDocument, (Func<Match, string>)(_ => string.Empty)).Returns(string.Empty).SetName("Replace all content with empty string");
                yield return new TestCaseData(".+", UpdateOptions.None, (Func<Match, string>)(_ => string.Empty)).Returns("\n\n\n").SetName("Replace each line with empty string");

                yield return new TestCaseData(".+", UpdateOptions.MatchEntireDocument, (Func<Match, string>)(_ => "Updated Content")).Returns("Updated Content").SetName("Replace all content with 'Updated Content'");
                yield return new TestCaseData(".+", UpdateOptions.None, (Func<Match, string>)(m => m.Value + " Updated Content")).Returns(string.Join('\n', [
                    "Hello, Updated Content",
                    "World! Updated Content",
                    "I'm the Updated Content",
                    "Document! Updated Content"
                ])).SetName("Prepend 'Updated Content' to each line");
            }
        }
    }
}

[TestFixture]
public class ExactTests
{
    public static readonly string[] LINES = ["Hello,", "World!", "I'm the", "Document!"];
    private TextEditor Editor;

    [SetUp]
    public void SetUp()
    {
        Editor = new TextEditor(new(LINES));
    }

    [Test]
    public void AddExactEdit_AllContentWithOneLine()
    {
        Editor.AddExactEdit(0, 0, 3, 9, _ => ["Updated content!"]);
        var compiled = CompiledDocument.FromBuilder(Editor);

        Assert.That(compiled.GetContent(), Is.EqualTo("Updated content!"));
    }

    [Test]
    public void AddExactEdit_UseContentToUpdate()
    {
        Editor.AddExactEdit(0, 0, 3, 9, content =>
        {
            return content.Select(line => line + " Updated content!").ToArray();
        });
        var compiled = CompiledDocument.FromBuilder(Editor);

        Assert.That(compiled.GetContent(), Is.EqualTo(string.Join('\n', [
            "Hello, Updated content!",
            "World! Updated content!",
            "I'm the Updated content!",
            "Document! Updated content!"
        ])));
    }

    [TestCaseSource(typeof(ExactTests), nameof(ReplaceContentWithEmptyCases))]
    public string AddExactEdit_ReplaceContentWithEmpty(
        int startingIndex,
        int startingColumn,
        int endingIndex,
        int endingColumn,
        Func<string[], string[]> content
    )
    {
        Editor.AddExactEdit(startingIndex, startingColumn, endingIndex, endingColumn, content);
        var compiled = CompiledDocument.FromBuilder(Editor);

        return compiled.GetContent();
    }

    public static IEnumerable ReplaceContentWithEmptyCases
    {
        get
        {
            yield return new TestCaseData(0, 0, 3, 9, (Func<string[], string[]>)(_ => [])).Returns(string.Empty).SetName("Replace all content with empty");
            yield return new TestCaseData(1, 0, 3, 9, (Func<string[], string[]>)(_ => [])).Returns("Hello,").SetName("Replace all content with empty except first line");
            yield return new TestCaseData(0, 0, 2, 7, (Func<string[], string[]>)(_ => [])).Returns("Document!").SetName("Replace all content with empty except last line");
            // yield return new TestCaseData(0, 0, 3, 9, (Func<string[], string[]>) (_ => ["", "", "", ""])).Returns("");
        }
    }
}
