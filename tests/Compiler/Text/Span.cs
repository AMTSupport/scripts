
using System.Collections;

namespace Text.Tests
{
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
            Assert.That(content, Is.EqualTo($"Hello,{Environment.NewLine}World!{Environment.NewLine}I'm the{Environment.NewLine}Document!"));
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

            Assert.That(content, Is.EqualTo($"World!{Environment.NewLine}I'm the"));
        }

        [Test]
        public void SetContent_UpdatesLinesWithNewContent()
        {
            var span = TextSpan.WrappingEntireDocument(document);
            int lengthChanged = span.SetContent(document, ["New Content"]);

            Assert.Multiple(() =>
            {
                Assert.That(lengthChanged, Is.EqualTo(-3));
                Assert.That(document.Lines[0], Is.EqualTo("New Content"));
                Assert.That(document.Lines, Has.Count.EqualTo(1));
            });

        }

        [Test]
        public void SetContent_UpdateMiddleLine() {
            var span = new TextSpan(1, 0, 1, lines[1].Length);
            int lengthChanged = span.SetContent(document, ["New Content"]);

            Assert.Multiple(() =>
            {
                Assert.That(lengthChanged, Is.EqualTo(0));
                Assert.That(document.Lines[1], Is.EqualTo("New Content"));
            });
        }

        [Test]
        public void SetContent_UpdateFirstLine() {
            var span = new TextSpan(0, 0, 0, lines[0].Length);
            int lengthChanged = span.SetContent(document, ["New Content"]);

            Assert.Multiple(() =>
            {
                Assert.That(lengthChanged, Is.EqualTo(0));
                Assert.That(document.Lines[0], Is.EqualTo("New Content"));
            });
        }

        [Test]
        public void SetContent_UpdateLastLine() {
            var span = new TextSpan(3, 0, 3, lines[^1].Length);
            int lengthChanged = span.SetContent(document, ["New Content"]);

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
            int lengthChanged = span.SetContent(document, ["New", "Content"]);

            Assert.Multiple(() =>
            {
                Assert.That(lengthChanged, Is.EqualTo(1));
                Assert.That(document.Lines[1], Is.EqualTo("New"));
                Assert.That(document.Lines[2], Is.EqualTo("Content"));
                Assert.That(document.Lines, Has.Count.EqualTo(5));
            });
        }

        [Test]
        public void SetContent_AppendAndPrependColumns()
        {
            var spanStart = new TextSpan(0, lines[0].Length - 1, 0, lines[0].Length - 1);
            int lengthChangedStart = spanStart.SetContent(document, [" beautiful"]);
            var spanEnd = new TextSpan(lines.Length - 1, 0, lines.Length - 1, 0);
            int lengthChangedEnd = spanEnd.SetContent(document, ["Awesome "]);

            Assert.Multiple(() =>
            {
                Assert.That(lengthChangedStart, Is.EqualTo(0));
                Assert.That(lengthChangedEnd, Is.EqualTo(0));
                Assert.That(document.Lines[0], Is.EqualTo("Hello beautiful,"));
                Assert.That(document.Lines[^1], Is.EqualTo("Awesome Document!"));
            });
        }

        [Test]
        public void SetContent_UpdateMiddleOfLines() {
            var span = new TextSpan(lines.Length - 2, 3, lines.Length - 2, 3);
            int lengthChanged = span.SetContent(document, [" not"]);

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
    }
}
