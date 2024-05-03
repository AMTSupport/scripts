using System.Text;

namespace Text
{
    public class TextSpan(int startingIndex, int startingColumn, int endingIndex, int endingColumn)
    {
        public int StartingIndex { get; set; } = startingIndex;
        public int StartingColumn { get; set; } = startingColumn;
        public int EndingIndex { get; set; } = endingIndex;
        public int EndingColumn { get; set; } = endingColumn;

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
            builder.AppendLine(document.Lines[StartingIndex][StartingColumn..]);
            for (int i = StartingIndex + 1; i < EndingIndex; i++)
            {
                builder.AppendLine(document.Lines[i]);
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
        public int SetContent(TextDocument document, string[] content)
        {
            var offset = 0;
            var lastLineAfter = document.Lines[EndingIndex][EndingColumn..];
            var firstLineBefore = document.Lines[StartingIndex][..StartingColumn];

            if (StartingIndex == EndingIndex)
            {
                // If the span is a single line and we took nothing from the line before or after, remove the line, since it will be empty.
                if (string.IsNullOrEmpty(firstLineBefore) || string.IsNullOrEmpty(lastLineAfter))
                {
                    document.Lines.RemoveAt(StartingIndex);
                    offset--;

                    // Short circuit if the new content is empty, there will be no need to update the document.
                    if (content.Length == 0)
                    {
                        return offset;
                    }
                }
                else
                {
                    document.Lines.RemoveAt(StartingIndex);
                    offset--;
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

            if (content.Length == 0)
            {
                if (!string.IsNullOrEmpty(firstLineBefore))
                {
                    document.Lines.Insert(StartingIndex, firstLineBefore);
                    offset++;
                }

                if (!string.IsNullOrEmpty(lastLineAfter))
                {
                    document.Lines.Insert(EndingIndex + offset, lastLineAfter);
                    offset++;
                }
            }
            else if (content.Length == 1)
            {
                if (StartingIndex == EndingIndex)
                {
                    document.Lines.Insert(StartingIndex, firstLineBefore + content[0] + lastLineAfter);
                    offset++;
                }
                else
                {
                    document.Lines.Insert(StartingIndex, firstLineBefore + content[0]);
                    offset++;

                    if (!string.IsNullOrEmpty(lastLineAfter))
                    {
                        document.Lines.Insert(EndingIndex + offset, lastLineAfter);
                        offset++;
                    }
                }
            }
            else
            {
                document.Lines.Insert(StartingIndex, firstLineBefore + content[0]);
                offset++;

                // Add the new content.
                for (int i = 1; i < content.Length; i++)
                {
                    document.Lines.Insert(StartingIndex + i, content[i]);
                    offset++;
                }

                document.Lines.Insert(EndingIndex + offset, content[^1] + lastLineAfter);
            }

            return offset;
        }

        public int RemoveContent(TextDocument document)
        {
            return SetContent(document, []);
        }
    }
}
