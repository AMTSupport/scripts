using System.Collections;
using Text;

namespace Compiler.Test.Text;

[TestFixture]
public class TextSpanTests
{
    private string[] lines;
    private TextDocument document;

    [SetUp]
    public void SetUp()
    {
        lines = [
            "Hello,",
            "World!",
            "I'm the",
            "Document!"
        ];

        document = new TextDocument(lines);
    }

    [Test]
    public void WrappingEntireDocument_ReturnsSpanWithCorrectIndices()
    {
        // Act
        var span = TextSpan.WrappingEntireDocument(document);

        // Assert
        Assert.Multiple(() =>
        {
            Assert.That(span.StartingIndex, Is.EqualTo(0));
            Assert.That(span.StartingColumn, Is.EqualTo(0));
            Assert.That(span.EndingIndex, Is.EqualTo(lines.Length - 1));
            Assert.That(span.EndingColumn, Is.EqualTo(expected: lines[^1].Length));
        });
    }

    [Test]
    public void Contains_ReturnsTrue_WhenIndexAndColumnAreWithinSpan()
    {
        var span = TextSpan.WrappingEntireDocument(document);
        bool result = span.Contains(1, 2);
        Assert.That(result, Is.True);
    }

    [Test]
    public void GetContent_EntireDocument()
    {
        var span = TextSpan.WrappingEntireDocument(document);
        string content = span.GetContent(document);
        Assert.That(content, Is.EqualTo($"Hello,\nWorld!\nI'm the\nDocument!"));
    }

    [Test]
    public void GetContent_SingleLineFromBeginingAndEndLines()
    {
        var spanFirst = new TextSpan(0, 0, 0, lines[0].Length);
        var contentFirst = spanFirst.GetContent(document);

        var spanLast = new TextSpan(3, 0, lines.Length - 1, lines[^1].Length);
        var contentLast = spanLast.GetContent(document);

        Assert.Multiple(() =>
        {
            Assert.That(contentFirst, Is.EqualTo(lines[0]));
            Assert.That(contentLast, Is.EqualTo(lines[^1]));
        });
    }

    [Test]
    public void GetContent_SingleLineFromMiddleLines()
    {
        var spans = new List<TextSpan>();
        var contents = new List<string>();

        for (int i = 1; i < lines.Length - 1; i++)
        {
            spans.Add(new TextSpan(i, 0, i, lines[i].Length));
            contents.Add(spans[i - 1].GetContent(document));
        }

        Assert.Multiple(() =>
        {
            for (int i = 0; i < contents.Count; i++)
            {
                Assert.That(contents[i], Is.EqualTo(lines[i + 1]));
            }
        });
    }

    [Test]
    public void GetContent_MultipleLines()
    {
        var span = new TextSpan(1, 0, 2, lines[2].Length);
        var content = span.GetContent(document);

        Assert.That(content, Is.EqualTo($"World!\nI'm the"));
    }

    [Test]
    public void SetContent_UpdatesLinesWithNewContent()
    {
        var span = TextSpan.WrappingEntireDocument(document);
        int lengthChanged = span.SetContent(document, UpdateOptions.None, ["New Content"]);

        Assert.Multiple(() =>
        {
            Assert.That(lengthChanged, Is.EqualTo(-3));
            Assert.That(document.Lines[0], Is.EqualTo("New Content"));
            Assert.That(document.Lines, Has.Count.EqualTo(1));
        });

    }

    [Test]
    public void SetContent_UpdateMiddleLine()
    {
        var span = new TextSpan(1, 0, 1, lines[1].Length);
        int lengthChanged = span.SetContent(document, UpdateOptions.None, ["New Content"]);

        Assert.Multiple(() =>
        {
            Assert.That(lengthChanged, Is.EqualTo(0));
            Assert.That(document.Lines[1], Is.EqualTo("New Content"));
        });
    }

    [Test]
    public void SetContent_UpdateFirstLine()
    {
        var span = new TextSpan(0, 0, 0, lines[0].Length);
        int lengthChanged = span.SetContent(document, UpdateOptions.None, ["New Content"]);

        Assert.Multiple(() =>
        {
            Assert.That(lengthChanged, Is.EqualTo(expected: 0));
            Assert.That(document.Lines, Has.Count.EqualTo(4));
            Assert.That(document.Lines[0], Is.EqualTo("New Content"));
        });
    }

    [Test]
    public void SetContent_UpdateLastLine()
    {
        var span = new TextSpan(3, 0, 3, lines[^1].Length);
        int lengthChanged = span.SetContent(document, UpdateOptions.None, ["New Content"]);

        Assert.Multiple(() =>
        {
            Assert.That(lengthChanged, Is.EqualTo(0));
            Assert.That(document.Lines[3], Is.EqualTo("New Content"));
        });
    }

    [Test]
    public void SetContent_InsertsNewLines()
    {
        var span = new TextSpan(1, 0, 1, lines[1].Length);
        int lengthChanged = span.SetContent(document, UpdateOptions.None, ["New", "Content"]);

        Assert.Multiple(() =>
        {
            Assert.That(lengthChanged, Is.EqualTo(1));
            Assert.That(document.Lines[1], Is.EqualTo("New"));
            Assert.That(document.Lines[2], Is.EqualTo("Content"));
        });
    }

    [Test]
    public void SetContent_AppendAndPrependColumns()
    {
        var spanStart = new TextSpan(0, lines[0].Length - 1, 0, lines[0].Length - 1);
        int lengthChangedStart = spanStart.SetContent(document, UpdateOptions.InsertInline, [" beautiful"]);
        var spanEnd = new TextSpan(lines.Length - 1, 0, lines.Length - 1, 0);
        int lengthChangedEnd = spanEnd.SetContent(document, UpdateOptions.InsertInline, ["Awesome "]);

        Assert.Multiple(() =>
        {
            Assert.That(lengthChangedStart, Is.EqualTo(0));
            Assert.That(lengthChangedEnd, Is.EqualTo(0));
            Assert.That(document.Lines[0], Is.EqualTo("Hello beautiful,"));
            Assert.That(document.Lines[^1], Is.EqualTo("Awesome Document!"));
        });
    }

    [Test]
    public void SetContent_UpdateMiddleOfLines()
    {
        var span = new TextSpan(lines.Length - 2, 3, lines.Length - 2, 3);
        int lengthChanged = span.SetContent(document, UpdateOptions.InsertInline, [" not"]);

        Assert.Multiple(() =>
        {
            Assert.That(lengthChanged, Is.EqualTo(0));
            Assert.That(document.Lines[^2], Is.EqualTo("I'm not the"));
        });
    }

    [Test]
    public void RemoveContent_RemovesContentFromLines()
    {
        var span = new TextSpan(startingIndex: 0, 0, 0, 6);
        var lengthChanged = span.RemoveContent(document);

        Assert.Multiple(() =>
        {
            Assert.That(lengthChanged, Is.EqualTo(-1));
            Assert.That(document.Lines[0], Is.EqualTo("World!"));
            Assert.That(document.Lines, Has.Count.EqualTo(3));
        });
    }

    [TestCaseSource(typeof(TestData), nameof(TestData.ContainsTestCases))]
    public bool ContainsTest(int index, int column)
    {
        var span = new TextSpan(0, 2, 2, 6);

        return span.Contains(index, column);
    }

    [TestCaseSource(typeof(TestData), nameof(TestData.GetContentTestCases))]
    public string GetContentTest(int startIdx, int startCol, int endIdx, int endCol)
    {
        var span = new TextSpan(startIdx, startCol, endIdx, endCol);

        return span.GetContent(document);
    }

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

    public static class TestData
    {
        public static IEnumerable ContainsTestCases
        {
            get
            {
                yield return new TestCaseData(1, 4).Returns(true).SetName("Index and column are within span");
                yield return new TestCaseData(0, 2).Returns(true).SetName("Index and column are at the start of the span");
                yield return new TestCaseData(3, 2).Returns(false).SetName("Index is outside the span");
                yield return new TestCaseData(2, 7).Returns(false).SetName("Column is outside the span");
                yield return new TestCaseData(2, 6).Returns(true).SetName("Index and column are at the end of the span");
                yield return new TestCaseData(0, 1).Returns(false).SetName("Index is at the start and column is outside the span");
            }
        }

        public static IEnumerable GetContentTestCases
        {
            get
            {
                yield return new TestCaseData(0, 0, 0, 0).Returns(string.Empty).SetName("Empty span");
                yield return new TestCaseData(0, 0, 2, 3).Returns("Hello,\nWorld!\nI'm").SetName("Multiple lines with partial content");
                yield return new TestCaseData(0, 0, 3, 9).Returns("Hello,\nWorld!\nI'm the\nDocument!").SetName("Entire document");
                yield return new TestCaseData(1, 0, 1, 6).Returns("World!").SetName("Single line");
                yield return new TestCaseData(1, 0, 2, 7).Returns("World!\nI'm the").SetName("Multiple lines");
            }
        }
    }
}
