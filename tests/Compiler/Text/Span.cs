
namespace Text.Tests
{
    [TestFixture]
    public class TextSpanTests
    {
        private TextDocument document;

        [SetUp]
        public void SetUp()
        {
            string[] lines = [
                "Hello,",
                "World!"
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
                Assert.That(span.EndingIndex, Is.EqualTo(1));
                Assert.That(span.EndingColumn, Is.EqualTo(6));
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
        public void GetContent_ReturnsCorrectContent()
        {
            var span = TextSpan.WrappingEntireDocument(document);
            string content = span.GetContent(document);
            Assert.That(content, Is.EqualTo($"Hello,{Environment.NewLine}World"));
        }

        [Test]
        public void SetContent_UpdatesLinesWithNewContent()
        {
            var span = TextSpan.WrappingEntireDocument(document);
            int linesChanged = span.SetContent(document, ["New Content"]);

            Assert.Multiple(() =>
            {
                Assert.That(linesChanged, Is.EqualTo(-1));
                Assert.That(document.Lines[0], Is.EqualTo("New Content"));
                Assert.That(document.Lines, Has.Count.EqualTo(1));
            });

        }

        [Test]
        public void RemoveContent_RemovesContentFromLines()
        {
            var span = new TextSpan(0, 0, 0, 6);

            // Act
            span.RemoveContent(document);

            Assert.Multiple(() =>
            {
                // Assert
                Assert.That(document.Lines[0], Is.EqualTo("World!"));
                Assert.That(document.Lines, Has.Count.EqualTo(1));
            });

        }
    }
}
