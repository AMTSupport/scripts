using System.Management.Automation;
using System.Text;
using JetBrains.Annotations;
using NLog;

namespace Text
{
    /// <summary>
    /// Specifies the options for updating a document.
    /// </summary>
    [Flags]
    public enum UpdateOptions
    {
        None = 0,
        MatchEntireDocument = 1,
        InsertInline = 2
    }

    public class TextSpan(
        [NonNegativeValue] int startingIndex,
        [NonNegativeValue] int startingColumn,
        [NonNegativeValue] int endingIndex,
        [NonNegativeValue] int endingColumn
    )
    {
        private readonly static Logger Logger = LogManager.GetCurrentClassLogger();

        [ValidateRange(0, int.MaxValue)] public int StartingIndex { get; set; } = startingIndex;
        [ValidateRange(0, int.MaxValue)] public int StartingColumn { get; set; } = startingColumn;
        [ValidateRange(0, int.MaxValue)] public int EndingIndex { get; set; } = endingIndex;
        [ValidateRange(0, int.MaxValue)] public int EndingColumn { get; set; } = endingColumn;

        public static TextSpan WrappingEntireDocument(TextDocument document)
        {
            return new TextSpan(0, 0, document.Lines.Count - 1, document.Lines[^1].Length);
        }

        public bool Contains(int index, int column)
        {
            if (index < StartingIndex || index > EndingIndex)
            {
                return false;
            }

            if (index == StartingIndex && column < StartingColumn)
            {
                return false;
            }

            if (index == EndingIndex && column > EndingColumn)
            {
                return false;
            }

            return true;
        }

        public string GetContent(TextDocument document)
        {
            if (StartingIndex == EndingIndex)
            {
                if (StartingColumn == 0 && EndingColumn == document.Lines[StartingIndex].Length)
                {
                    return document.Lines[StartingIndex];
                }

                if (StartingColumn == EndingColumn)
                {
                    return string.Empty;
                }

                return document.Lines[StartingIndex][StartingColumn..EndingColumn];
            }

            var builder = new StringBuilder();
            builder.Append(document.Lines[StartingIndex][StartingColumn..] + '\n');
            for (int i = StartingIndex + 1; i < EndingIndex; i++)
            {
                builder.Append(document.Lines[i] + '\n');
            }
            builder.Append(document.Lines[EndingIndex][..EndingColumn]);

            return builder.ToString();
        }

        /// <summary>
        /// Set the content of the span to the provided content.
        /// </summary>
        /// <param name="lines">
        /// The lines to update.
        /// </param>
        /// <param name="content">
        /// The content to set the span to.
        /// </param>
        /// <returns>
        /// The number of lines added or removed by the update.
        /// </returns>
        public int SetContent(
            [NotNull] TextDocument document,
            [NotNull] UpdateOptions options,
            [NotNull] string[] content
        )
        {
            if (StartingIndex < 0 || StartingIndex >= document.Lines.Count)
            {
                Logger.Error("Starting index {0} is out of range for document with {1} lines", StartingIndex, document.Lines.Count);
                throw new ArgumentOutOfRangeException(nameof(StartingIndex));
            }

            if (EndingIndex < 0 || EndingIndex >= document.Lines.Count)
            {
                Logger.Error("Ending index {0} is out of range for document with {1} lines", EndingIndex, document.Lines.Count);
                throw new ArgumentOutOfRangeException(nameof(EndingIndex));
            }

            if (StartingIndex > EndingIndex)
            {
                Logger.Error("Starting index {0} is greater than ending index {1}", StartingIndex, EndingIndex);
                throw new ArgumentOutOfRangeException(nameof(StartingIndex));
            }

            if (StartingIndex == EndingIndex && StartingColumn > EndingColumn)
            {
                Logger.Error("Starting column {0} is greater than ending column {1} on the same line", StartingColumn, EndingColumn);
                throw new ArgumentOutOfRangeException(nameof(StartingColumn));
            }

            var startingLine = document.Lines[StartingIndex];
            if (startingLine.Length < StartingColumn)
            {
                Logger.Error("Starting column {0} is out of range for line with {1} characters", StartingColumn, startingLine.Length);
                throw new ArgumentOutOfRangeException(nameof(StartingColumn));
            }

            var endingLine = document.Lines[EndingIndex];
            if (endingLine.Length < EndingColumn)
            {
                Logger.Error("Ending column {0} is out of range for line with {1} characters", EndingColumn, endingLine.Length);
                throw new ArgumentOutOfRangeException(nameof(EndingColumn));
            }

            var offset = 0;
            var firstLineBefore = startingLine[..StartingColumn];
            var lastLineAfter = endingLine[EndingColumn..];

            if (StartingIndex == EndingIndex)
            {
                document.Lines.RemoveAt(StartingIndex);
                offset--;

                // Short circuit if the new content is empty, there will be no need to update the document.
                if (string.IsNullOrEmpty(firstLineBefore) && string.IsNullOrEmpty(lastLineAfter) && content.Length == 0)
                {
                    return offset;
                }
            }
            else
            {
                // Remove all lines in the span to get a clean slate.
                for (int i = StartingIndex; i <= EndingIndex; i++)
                {
                    document.Lines.RemoveAt(StartingIndex);
                    offset--;
                }
            }

            if (options.HasFlag(UpdateOptions.InsertInline))
            {
                var lineContent = new StringBuilder();

                if (!string.IsNullOrEmpty(firstLineBefore))
                {
                    lineContent.Append(firstLineBefore);
                }

                if (content.Length > 1)
                {
                    lineContent.Append(content[0]);

                    document.Lines.InsertRange(StartingIndex, content.Skip(1));
                    offset += content.Length - 1;
                }
                else
                {
                    lineContent.Append(content[0]);
                }

                if (!string.IsNullOrEmpty(lastLineAfter))
                {
                    if (StartingIndex != EndingIndex || content.Length > 1)
                    {
                        document.Lines[EndingIndex + offset] += lastLineAfter;
                    }
                    else
                    {
                        lineContent.Append(lastLineAfter);
                    }
                }

                document.Lines.Insert(StartingIndex, lineContent.ToString());
                offset++;
            }
            else
            {
                var insertingAfterStartingIndex = false;
                if (!string.IsNullOrEmpty(firstLineBefore))
                {
                    document.Lines.Insert(StartingIndex, firstLineBefore);
                    insertingAfterStartingIndex = true;
                    offset++;
                }

                if (content.Length > 0)
                {
                    document.Lines.InsertRange(StartingIndex + (insertingAfterStartingIndex ? 1 : 0), content);
                    offset += content.Length;
                }

                if (!string.IsNullOrEmpty(lastLineAfter))
                {
                    document.Lines.Insert(EndingIndex + offset + 1, lastLineAfter);
                    offset++;
                }
            }

            return offset;
        }

        public int RemoveContent(TextDocument document)
        {
            return SetContent(document, UpdateOptions.None, []);
        }
    }
}
