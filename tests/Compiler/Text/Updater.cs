using System.Text.RegularExpressions;
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
    private string[] lines;
    private TextEditor Editor;

    [SetUp]
    public void SetUp()
    {
        lines = [
            "Hello,",
            "World!",
            "I'm the",
            "Document!"
        ];

        Editor = new TextEditor(new(lines));
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
        Editor.AddRegexEdit(".*", true, _ => "Updated content!");
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

    [Test]
    public void AddRegexEdit_ReplaceContentWithEmpty()
    {
        Editor.AddRegexEdit(".*", _ => "");
        Editor.ApplyEdits();

        Assert.That(Editor.GetContent(), Is.EqualTo(""));
    }
}
