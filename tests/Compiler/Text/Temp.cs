using Text;

namespace Compiler.Test.Text;

[TestFixture]
public class TextSpanTests2
{
    [Test]
    public void SetContent_RemovesSingleLineSpan_WhenContentIsEmpty()
    {
        var document = new TextDocument(["Hello, World!"]);

        var span = new TextSpan(0, 0, 0, 13);
        var offset = span.SetContent(document, UpdateOptions.None, []);

        Assert.Multiple(() =>
        {
            Assert.That(offset, Is.EqualTo(-1));
            Assert.That(document.Lines, Is.Empty);
        });

    }

    [Test]
    public void SetContent_RemovesMultiLineSpan_WhenContentIsEmpty()
    {
        var document = new TextDocument(["Line 1", "Line 2", "Line 3"]);

        var span = new TextSpan(0, 0, 2, 6);
        var offset = span.SetContent(document, UpdateOptions.None, []);

        Assert.Multiple(() =>
        {
            Assert.That(offset, Is.EqualTo(-3));
            Assert.That(document.Lines, Is.Empty);
        });

    }

    [Test]
    public void SetContent_ReplacesSingleLineSpan_WhenContentHasSingleLine()
    {
        var document = new TextDocument(["Hello, World!"]);

        var span = new TextSpan(0, 0, 0, 13);
        var offset = span.SetContent(document, UpdateOptions.None, ["New Content"]);

        Assert.Multiple(() =>
        {
            Assert.That(offset, Is.EqualTo(0));
            Assert.That(document.Lines, Has.Count.EqualTo(1));
            Assert.That(document.Lines[0], Is.EqualTo("New Content"));
        });

    }

    [Test]
    public void SetContent_ReplacesMultiLineSpan_WhenContentHasMultipleLines()
    {
        var document = new TextDocument(["Line 1", "Line 2", "Line 3"]);

        var span = new TextSpan(0, 0, 2, 6);
        var offset = span.SetContent(document, UpdateOptions.None, ["New Line 1", "New Line 2", "New Line 3"]);

        Assert.Multiple(() =>
        {
            Assert.That(offset, Is.EqualTo(0));
            Assert.That(document.Lines, Has.Count.EqualTo(3));
            Assert.That(document.Lines[0], Is.EqualTo("New Line 1"));
            Assert.That(document.Lines[1], Is.EqualTo("New Line 2"));
            Assert.That(document.Lines[2], Is.EqualTo("New Line 3"));
        });

    }

    [Test]
    public void SetContent_InsertsContentAtStart_WhenSpanIsAtStartOfDocument()
    {
        var document = new TextDocument(["Line 1", "Line 2", "Line 3"]);

        var span = new TextSpan(0, 0, 0, 0);
        var offset = span.SetContent(document, UpdateOptions.None, ["New Line 1", "New Line 2", "New Line 3"]);

        Assert.Multiple(() =>
        {
            Assert.That(offset, Is.EqualTo(3));
            Assert.That(document.Lines, Has.Count.EqualTo(6));
            Assert.That(document.Lines[0], Is.EqualTo("New Line 1"));
            Assert.That(document.Lines[1], Is.EqualTo("New Line 2"));
            Assert.That(document.Lines[2], Is.EqualTo("New Line 3"));
            Assert.That(document.Lines[3], Is.EqualTo("Line 1"));
            Assert.That(document.Lines[4], Is.EqualTo("Line 2"));
            Assert.That(document.Lines[5], Is.EqualTo("Line 3"));
        });

    }

    [Test]
    public void SetContent_InsertsContentAtEnd_WhenSpanIsAtEndOfDocument()
    {
        var document = new TextDocument(["Line 1", "Line 2", "Line 3"]);

        var span = new TextSpan(2, 6, 2, 6);
        var offset = span.SetContent(document, UpdateOptions.None, ["New Line 1", "New Line 2", "New Line 3"]);

        Assert.Multiple(() =>
        {
            Assert.That(offset, Is.EqualTo(3));
            Assert.That(document.Lines, Has.Count.EqualTo(6));
            Assert.That(document.Lines[0], Is.EqualTo("Line 1"));
            Assert.That(document.Lines[1], Is.EqualTo("Line 2"));
            Assert.That(document.Lines[2], Is.EqualTo("Line 3"));
            Assert.That(document.Lines[3], Is.EqualTo("New Line 1"));
            Assert.That(document.Lines[4], Is.EqualTo("New Line 2"));
            Assert.That(document.Lines[5], Is.EqualTo("New Line 3"));
        });
    }

    [Test]
    public void SetContent_InsertsContentInMiddle_WhenSpanIsInMiddleOfDocument()
    {
        var document = new TextDocument(["Line 1", "Line 2", "Line 3"]);

        var span = new TextSpan(1, 0, 1, 0);
        var offset = span.SetContent(document, UpdateOptions.None, ["New Line 1", "New Line 2", "New Line 3"]);

        Assert.Multiple(() =>
        {
            Assert.That(offset, Is.EqualTo(3));
            Assert.That(document.Lines, Has.Count.EqualTo(6));
            Assert.That(document.Lines[0], Is.EqualTo("Line 1"));
            Assert.That(document.Lines[1], Is.EqualTo("New Line 1"));
            Assert.That(document.Lines[2], Is.EqualTo("New Line 2"));
            Assert.That(document.Lines[3], Is.EqualTo("New Line 3"));
            Assert.That(document.Lines[4], Is.EqualTo("Line 2"));
            Assert.That(document.Lines[5], Is.EqualTo("Line 3"));
        });
    }
}
