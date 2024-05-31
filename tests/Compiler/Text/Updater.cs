using System.Collections;
using Text;

namespace Compiler.Test.Text;

[TestFixture]
public class PatternTests
{
    private string[] lines;
    private TextEditor Editor;

    [SetUp]
    public void SetUp()
    {
        lines = [
            "@\"",
            "Doing cool stuff with this multiline string!",
            "",
            "This is the end of the string!",
            "\"@"
        ];

        Editor = new TextEditor(new(lines));
    }

    [Test]
    public void AddPatternEdit_ReplaceAllContent()
    {
        Editor.AddPatternEdit(openingPattern: "@\"", "\"@", _ => ["Updated content!"]);
        Editor.ApplyEdits();

        Assert.That(Editor.GetContent(), Is.EqualTo("Updated content!"));
    }

    [Test]
    public void AddPatternEdit_UseContentToUpdate()
    {
        Editor.AddPatternEdit("@\"", "\"@", content =>
        {
            return content.Select(line => line + "Updated content!").ToArray();
        });
        Editor.ApplyEdits();

        Assert.That(Editor.GetContent(), Is.EqualTo($"@\"Updated content!\nDoing cool stuff with this multiline string!Updated content!\nUpdated content!\nThis is the end of the string!Updated content!\n\"@Updated content!"));
    }

    [Test]
    public void AddPatternEdit_ReplaceContentWithEmpty()
    {
        Editor.AddPatternEdit("@\"", "\"@", _ => ["@\"", "\"@"]);
        Editor.ApplyEdits();

        Assert.That(Editor.GetContent(), Is.EqualTo($"@\"\n\"@"));
    }
}

[TestFixture]
public class RegexTests
{
    public static readonly string[] LINES = ["Hello,", "World!", "I'm the", "Document!"];

    private TextEditor Editor;

    [SetUp]
    public void SetUp()
    {
        Editor = new TextEditor(new(LINES));
    }

    [Test]
    public void AddRegexEdit_ReplaceEachLine()
    {
        Editor.AddRegexEdit("^.*$", _ => "Updated content!");
        Editor.ApplyEdits();

        Assert.That(Editor.GetContent(), Is.EqualTo($"Updated content!\nUpdated content!\nUpdated content!\nUpdated content!"));
    }

    [Test]
    public void AddRegexEdit_ReplaceAllContent()
    {
        Editor.AddRegexEdit(".+", UpdateOptions.MatchEntireDocument, _ => "Updated content!");
        Editor.ApplyEdits();

        Assert.That(Editor.GetContent(), Is.EqualTo("Updated content!"));
    }

    [Test]
    public void AddRegexEdit_UseContentToUpdate()
    {
        Editor.AddRegexEdit(".*", match =>
        {
            return match.Value + " Updated content!";
        });
        Editor.ApplyEdits();

        Assert.That(Editor.GetContent(), Is.EqualTo(string.Join('\n', [
            "Hello, Updated content!",
            "World! Updated content!",
            "I'm the Updated content!",
            "Document! Updated content!"
        ])));
    }

    [Test, TestCase(UpdateOptions.None), TestCase(UpdateOptions.MatchEntireDocument)]
    public void AddRegexEdit_ReplaceContentWithEmpty(UpdateOptions options)
    {
        Editor.AddRegexEdit(".*", options, _ => "");
        Editor.ApplyEdits();

        Assert.That(Editor.GetContent(), Is.EqualTo(""));
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
        Editor.ApplyEdits();

        Assert.That(Editor.GetContent(), Is.EqualTo("Updated content!"));
    }

    [Test]
    public void AddExactEdit_UseContentToUpdate()
    {
        Editor.AddExactEdit(0, 0, 3, 9, content =>
        {
            return content.Select(line => line + " Updated content!").ToArray();
        });
        Editor.ApplyEdits();

        Assert.That(Editor.GetContent(), Is.EqualTo(string.Join('\n', [
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
        Editor.ApplyEdits();

        return Editor.GetContent();
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
