// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using Compiler.Text;

namespace Compiler.Test.Text;

[TestFixture]
public class TextSpanTests {
    private List<string> Lines;
    private TextDocument Document;

    [SetUp]
    public void SetUp() {
        this.Lines = new List<string>([
            "Hello,",
            "World!",
            "I'm the",
            "Document!"
        ]);

        this.Document = new TextDocument([.. this.Lines]);
    }

    [Test, TestCaseSource(typeof(TestData), nameof(TestData.WrappingEntireDocumentTextCases))]
    public TextSpan WrappingEntireDocument(string[] lines) {
        var span = TextSpan.WrappingEntireDocument(lines);

        Assert.Multiple(() => {
            Assert.That(span.StartingIndex, Is.EqualTo(0));
            Assert.That(span.StartingColumn, Is.EqualTo(0));
            Assert.That(span.EndingIndex, Is.EqualTo(Math.Max(0, lines.Length - 1)));

            if (lines.Length == 0) {
                Assert.That(span.EndingColumn, Is.EqualTo(0));
            } else {
                Assert.That(span.EndingColumn, Is.EqualTo(lines[^1].Length));
            }
        });

        Console.WriteLine(span);

        return span;
    }

    [Test]
    public void Contains_ReturnsTrue_WhenIndexAndColumnAreWithinSpan() {
        var span = TextSpan.WrappingEntireDocument(this.Document);
        var result = span.Contains(1, 2);
        Assert.That(result, Is.True);
    }

    [Test]
    public void GetContent_SingleLineFromBeginingAndEndLines() {
        var spanFirst = TextSpan.New(0, 0, 0, this.Lines[0].Length).Unwrap();
        var contentFirst = spanFirst.GetContent(this.Document);

        var spanLast = TextSpan.New(3, 0, this.Lines.Count - 1, this.Lines[^1].Length).Unwrap();
        var contentLast = spanLast.GetContent(this.Document);

        Assert.Multiple(() => {
            Assert.That(contentFirst, Is.EqualTo(this.Lines[0]));
            Assert.That(contentLast, Is.EqualTo(this.Lines[^1]));
        });
    }

    [Test]
    public void SetContent_UpdatesLinesWithNewContent() {
        var span = TextSpan.WrappingEntireDocument(this.Document);
        var lengthChanged = span.SetContent(this.Lines, UpdateOptions.None, ["New Content"]);

        Assert.Multiple(() => {
            Assert.That(lengthChanged, Is.EqualTo(-3));
            Assert.That(this.Lines[0], Is.EqualTo("New Content"));
            Assert.That(this.Lines, Has.Count.EqualTo(1));
        });

    }

    [Test]
    public void SetContent_UpdateMiddleLine() {
        var span = TextSpan.New(1, 0, 1, this.Lines[1].Length).Unwrap();
        var lengthChanged = span.SetContent(this.Lines, UpdateOptions.None, ["New Content"]);

        Assert.Multiple(() => {
            Assert.That(lengthChanged, Is.EqualTo(0));
            Assert.That(this.Lines[1], Is.EqualTo("New Content"));
        });
    }

    [Test]
    public void SetContent_UpdateFirstLine() {
        var span = TextSpan.New(0, 0, 0, this.Lines[0].Length).Unwrap();
        var lengthChanged = span.SetContent(this.Lines, UpdateOptions.None, ["New Content"]);

        Assert.Multiple(() => {
            Assert.That(lengthChanged, Is.EqualTo(expected: 0));
            Assert.That(this.Lines, Has.Count.EqualTo(4));
            Assert.That(this.Lines[0], Is.EqualTo("New Content"));
        });
    }

    [Test]
    public void SetContent_UpdateLastLine() {
        var span = TextSpan.New(3, 0, 3, this.Lines[^1].Length).Unwrap();
        var lengthChanged = span.SetContent(this.Lines, UpdateOptions.None, ["New Content"]);

        Assert.Multiple(() => {
            Assert.That(lengthChanged, Is.EqualTo(0));
            Assert.That(this.Lines[3], Is.EqualTo("New Content"));
        });
    }

    [Test]
    public void SetContent_InsertsNewLines() {
        var span = TextSpan.New(1, 0, 1, this.Lines[1].Length).Unwrap();
        var lengthChanged = span.SetContent(this.Lines, UpdateOptions.None, ["New", "Content"]);

        Assert.Multiple(() => {
            Assert.That(lengthChanged, Is.EqualTo(1));
            Assert.That(this.Lines[1], Is.EqualTo("New"));
            Assert.That(this.Lines[2], Is.EqualTo("Content"));
        });
    }

    [Test]
    public void SetContent_AppendAndPrependColumns() {
        var spanStart = TextSpan.New(0, this.Lines[0].Length - 1, 0, this.Lines[0].Length - 1).Unwrap();
        var lengthChangedStart = spanStart.SetContent(this.Lines, UpdateOptions.InsertInline, [" beautiful"]);
        var spanEnd = TextSpan.New(this.Lines.Count - 1, 0, this.Lines.Count - 1, 0).Unwrap();
        var lengthChangedEnd = spanEnd.SetContent(this.Lines, UpdateOptions.InsertInline, ["Awesome "]);

        Assert.Multiple(() => {
            Assert.That(lengthChangedStart, Is.EqualTo(0));
            Assert.That(lengthChangedEnd, Is.EqualTo(0));
            Assert.That(this.Lines[0], Is.EqualTo("Hello beautiful,"));
            Assert.That(this.Lines[^1], Is.EqualTo("Awesome Document!"));
        });
    }

    [Test]
    public void SetContent_UpdateMiddleOfLines() {
        var span = TextSpan.New(this.Lines.Count - 2, 3, this.Lines.Count - 2, 3).Unwrap();
        var lengthChanged = span.SetContent(this.Lines, UpdateOptions.InsertInline, [" not"]);

        Assert.Multiple(() => {
            Assert.That(lengthChanged, Is.EqualTo(0));
            Assert.That(this.Lines[^2], Is.EqualTo("I'm not the"));
        });
    }

    [Test]
    public void RemoveContent_RemovesContentFromLines() {
        var span = TextSpan.New(startingIndex: 0, 0, 0, 6).Unwrap();
        var lengthChanged = span.RemoveContent(this.Lines);

        Assert.Multiple(() => {
            Assert.That(lengthChanged, Is.EqualTo(-1));
            Assert.That(this.Lines[0], Is.EqualTo("World!"));
            Assert.That(this.Lines, Has.Count.EqualTo(3));
        });
    }

    [TestCaseSource(typeof(TestData), nameof(TestData.ContainsTestCases))]
    public bool ContainsTest(int index, int column) {
        var span = TextSpan.New(0, 2, 2, 6).Unwrap();

        return span.Contains(index, column);
    }

    [TestCaseSource(typeof(TestData), nameof(TestData.GetContentTestCases))]
    public string GetContent(
        string[] lines,
        TextSpan span
    ) {
        Assert.Multiple(() => {
            Assert.That(span, Is.Not.Null);
            Assert.That(span.StartingIndex, Is.GreaterThanOrEqualTo(0));
            Assert.That(span.StartingColumn, Is.GreaterThanOrEqualTo(0));
            Assert.That(span.EndingIndex, Is.GreaterThanOrEqualTo(0));
            Assert.That(span.EndingIndex, Is.LessThanOrEqualTo(Math.Max(0, lines.Length - 1)));
        });

        return span.GetContent(lines);
    }

    [Test]
    public void SetContent_RemovesSingleLineSpan_WhenContentIsEmpty() {
        var lines = new List<string>(["Hello, World!"]);

        var span = TextSpan.New(0, 0, 0, 13).Unwrap();
        var offset = span.SetContent(lines, UpdateOptions.None, []);

        Assert.Multiple(() => {
            Assert.That(offset, Is.EqualTo(-1));
            Assert.That(lines, Is.Empty);
        });

    }

    [Test]
    public void SetContent_RemovesMultiLineSpan_WhenContentIsEmpty() {
        var lines = new List<string>(["Line 1", "Line 2", "Line 3"]);

        var span = TextSpan.New(0, 0, 2, 6).Unwrap();
        var offset = span.SetContent(lines, UpdateOptions.None, []);

        Assert.Multiple(() => {
            Assert.That(offset, Is.EqualTo(-3));
            Assert.That(lines, Is.Empty);
        });

    }

    [Test]
    public void SetContent_ReplacesSingleLineSpan_WhenContentHasSingleLine() {
        var lines = new List<string>(["Hello, World!"]);

        var span = TextSpan.New(0, 0, 0, 13).Unwrap();
        var offset = span.SetContent(lines, UpdateOptions.None, ["New Content"]);

        Assert.Multiple(() => {
            Assert.That(offset, Is.EqualTo(0));
            Assert.That(lines, Has.Count.EqualTo(1));
            Assert.That(lines[0], Is.EqualTo("New Content"));
        });

    }

    [Test]
    public void SetContent_ReplacesMultiLineSpan_WhenContentHasMultipleLines() {
        var lines = new List<string>(["Line 1", "Line 2", "Line 3"]);

        var span = TextSpan.New(0, 0, 2, 6).Unwrap();
        var offset = span.SetContent(lines, UpdateOptions.None, ["New Line 1", "New Line 2", "New Line 3"]);

        Assert.Multiple(() => {
            Assert.That(offset, Is.EqualTo(0));
            Assert.That(lines, Has.Count.EqualTo(3));
            Assert.That(lines[0], Is.EqualTo("New Line 1"));
            Assert.That(lines[1], Is.EqualTo("New Line 2"));
            Assert.That(lines[2], Is.EqualTo("New Line 3"));
        });

    }

    [Test]
    public void SetContent_InsertsContentAtStart_WhenSpanIsAtStartOfDocument() {
        var lines = new List<string>(["Line 1", "Line 2", "Line 3"]);

        var span = TextSpan.New(0, 0, 0, 0).Unwrap();
        var offset = span.SetContent(lines, UpdateOptions.None, ["New Line 1", "New Line 2", "New Line 3"]);

        Assert.Multiple(() => {
            Assert.That(offset, Is.EqualTo(3));
            Assert.That(lines, Has.Count.EqualTo(6));
            Assert.That(lines[0], Is.EqualTo("New Line 1"));
            Assert.That(lines[1], Is.EqualTo("New Line 2"));
            Assert.That(lines[2], Is.EqualTo("New Line 3"));
            Assert.That(lines[3], Is.EqualTo("Line 1"));
            Assert.That(lines[4], Is.EqualTo("Line 2"));
            Assert.That(lines[5], Is.EqualTo("Line 3"));
        });

    }

    [Test]
    public void SetContent_InsertsContentAtEnd_WhenSpanIsAtEndOfDocument() {
        var lines = new List<string>(["Line 1", "Line 2", "Line 3"]);

        var span = TextSpan.New(2, 6, 2, 6).Unwrap();
        var offset = span.SetContent(lines, UpdateOptions.None, ["New Line 1", "New Line 2", "New Line 3"]);

        Assert.Multiple(() => {
            Assert.That(offset, Is.EqualTo(3));
            Assert.That(lines, Has.Count.EqualTo(6));
            Assert.That(lines[0], Is.EqualTo("Line 1"));
            Assert.That(lines[1], Is.EqualTo("Line 2"));
            Assert.That(lines[2], Is.EqualTo("Line 3"));
            Assert.That(lines[3], Is.EqualTo("New Line 1"));
            Assert.That(lines[4], Is.EqualTo("New Line 2"));
            Assert.That(lines[5], Is.EqualTo("New Line 3"));
        });
    }

    [Test]
    public void SetContent_InsertsContentInMiddle_WhenSpanIsInMiddleOfDocument() {
        var lines = new List<string>(["Line 1", "Line 2", "Line 3"]);

        var span = TextSpan.New(1, 0, 1, 0).Unwrap();
        var offset = span.SetContent(lines, UpdateOptions.None, ["New Line 1", "New Line 2", "New Line 3"]);

        Assert.Multiple(() => {
            Assert.That(offset, Is.EqualTo(3));
            Assert.That(lines, Has.Count.EqualTo(6));
            Assert.That(lines[0], Is.EqualTo("Line 1"));
            Assert.That(lines[1], Is.EqualTo("New Line 1"));
            Assert.That(lines[2], Is.EqualTo("New Line 2"));
            Assert.That(lines[3], Is.EqualTo("New Line 3"));
            Assert.That(lines[4], Is.EqualTo("Line 2"));
            Assert.That(lines[5], Is.EqualTo("Line 3"));
        });
    }

    [Test]
    public void SetContent_InsertsContentAtEndOfLastString_WhenInlineModeAndContentIsLargerThan1() {
        var lines = new List<string>(["Hello, World!"]);

        var span = TextSpan.New(0, 0, 0, 0).Unwrap();
        var offset = span.SetContent(lines, UpdateOptions.InsertInline, ["New", "Super cool", "This is a cool "]);

        Assert.Multiple(() => {
            Assert.That(offset, Is.EqualTo(2));
            Assert.That(lines, Has.Count.EqualTo(3));
            Assert.That(lines[0], Is.EqualTo("New"));
            Assert.That(lines[1], Is.EqualTo("Super cool"));
            Assert.That(lines[2], Is.EqualTo("This is a cool Hello, World!"));
        });
    }

    [Test]
    public void GetContent_ContentFromMiddleOfLines_AndPartialLine() {
        var lines = new List<string>(["Starting", "Hello, World!", "Ending"]);

        var span = TextSpan.New(1, 0, 1, 5).Unwrap();
        var content = span.GetContent([.. lines]);

        Assert.That(content, Is.EqualTo("Hello"));
    }

    public static class TestData {
        private static readonly List<string> EmptyLines = [];
        private static readonly List<string> SingleLine = new(["Hello, World!, I'm the Document!"]);
        private static readonly List<string> TwoLines = new(["Hello, World!", "I'm the Document!"]);
        private static readonly List<string> FourLines = new(["Hello,", "World!", "I'm the", "Document!"]);
        private static readonly List<string> TenLines = new(["Line1", "Line2", "Line3", "Line4", "Line5", "Line6", "Line7", "Line8", "Line9", "Line10"]);

        public static IEnumerable ContainsTestCases {
            get {
                yield return new TestCaseData(1, 4).Returns(true).SetDescription("Index and column are within span");
                yield return new TestCaseData(0, 2).Returns(true).SetDescription("Index and column are at the start of the span");
                yield return new TestCaseData(3, 2).Returns(false).SetDescription("Index is outside the span");
                yield return new TestCaseData(2, 7).Returns(false).SetDescription("Column is outside the span");
                yield return new TestCaseData(2, 6).Returns(true).SetDescription("Index and column are at the end of the span");
                yield return new TestCaseData(0, 1).Returns(false).SetDescription("Index is at the start and column is outside the span");
            }
        }

        public static IEnumerable GetContentTestCases {
            get {
                yield return new TestCaseData(
                    EmptyLines.ToArray(),
                    TextSpan.New(0, 0, 0, 0).Unwrap()
                ).SetCategory("Empty span").Returns(string.Empty);

                yield return new TestCaseData(
                    TenLines.ToArray(),
                    TextSpan.New(0, 0, 9, 6).Unwrap()
                ).SetCategory("Ten lines").Returns("Line1\nLine2\nLine3\nLine4\nLine5\nLine6\nLine7\nLine8\nLine9\nLine10");


                yield return new TestCaseData(
                    SingleLine.ToArray(),
                    TextSpan.New(0, 0, 0, 32).Unwrap()
                ).SetCategory("Single line").Returns("Hello, World!, I'm the Document!").SetDescription("Full span");

                yield return new TestCaseData(
                    SingleLine.ToArray(),
                    TextSpan.New(0, 0, 0, 7).Unwrap()
                ).SetCategory("Single line").Returns("Hello, ").SetDescription("Partial span start");

                yield return new TestCaseData(
                    SingleLine.ToArray(),
                    TextSpan.New(0, 7, 0, 13).Unwrap()
                ).SetCategory("Single line").Returns("World!").SetDescription("Partial span end");

                yield return new TestCaseData(
                    SingleLine.ToArray(),
                    TextSpan.New(0, 2, 0, 10).Unwrap()
                ).SetCategory("Single line").Returns("llo, Wor").SetDescription("Partial span start and end");


                yield return new TestCaseData(
                    TwoLines.ToArray(),
                    TextSpan.New(0, 0, 1, 17).Unwrap()
                ).SetCategory("Two lines").Returns("Hello, World!\nI'm the Document!").SetDescription("Full span");

                yield return new TestCaseData(
                    TwoLines.ToArray(),
                    TextSpan.New(0, 7, 1, 7).Unwrap()
                ).SetCategory("Two lines").Returns("World!\nI'm the").SetDescription("Partial first and last");

                yield return new TestCaseData(
                    TwoLines.ToArray(),
                    TextSpan.New(0, 0, 0, 13).Unwrap()
                ).SetCategory("Two lines").Returns("Hello, World!").SetDescription("Take first line");

                yield return new TestCaseData(
                    TwoLines.ToArray(),
                    TextSpan.New(1, 0, 1, 7).Unwrap()
                ).SetCategory("Two lines").Returns("I'm the").SetDescription("Take last line");


                yield return new TestCaseData(
                    FourLines.ToArray(),
                    TextSpan.New(0, 0, 3, 9).Unwrap()
                ).SetCategory("Four lines").Returns("Hello,\nWorld!\nI'm the\nDocument!").SetDescription("Full span");

                yield return new TestCaseData(
                    FourLines.ToArray(),
                    TextSpan.New(1, 3, 3, 4).Unwrap()
                ).SetCategory("Four lines").Returns("ld!\nI'm the\nDocu").SetDescription("Partial first, middle and partial last");

                yield return new TestCaseData(
                    FourLines.ToArray(),
                    TextSpan.New(0, 0, 0, 6).Unwrap()
                ).SetCategory("Four lines").Returns("Hello,").SetDescription("Take first line");

                yield return new TestCaseData(
                    FourLines.ToArray(),
                    TextSpan.New(0, 0, 1, 6).Unwrap()
                ).SetCategory("Four lines").Returns("Hello,\nWorld!").SetDescription("Take first two lines");

                yield return new TestCaseData(
                    FourLines.ToArray(),
                    TextSpan.New(2, 0, 3, 9).Unwrap()
                ).SetCategory("Four lines").Returns("I'm the\nDocument!").SetDescription("Take last two lines");

                yield return new TestCaseData(
                    FourLines.ToArray(),
                    TextSpan.New(3, 0, 3, 9).Unwrap()
                ).SetCategory("Four lines").Returns("Document!").SetDescription("Take last line");
            }
        }

        public static IEnumerable WrappingEntireDocumentTextCases {
            get {
                yield return new TestCaseData(arg: EmptyLines.ToArray()).SetCategory("Empty").Returns(TextSpan.New(0, 0, 0, 0).Unwrap());
                yield return new TestCaseData(arg: SingleLine.ToArray()).SetCategory("Single line").Returns(TextSpan.New(0, 0, 0, 32).Unwrap());
                yield return new TestCaseData(arg: TwoLines.ToArray()).SetCategory("Two lines").Returns(TextSpan.New(0, 0, 1, 17).Unwrap());
                yield return new TestCaseData(arg: FourLines.ToArray()).SetCategory("Four lines").Returns(TextSpan.New(0, 0, 3, 9).Unwrap());
                yield return new TestCaseData(arg: TenLines.ToArray()).SetCategory("Ten lines").Returns(TextSpan.New(0, 0, 9, 6).Unwrap());
            }
        }
    }
}
