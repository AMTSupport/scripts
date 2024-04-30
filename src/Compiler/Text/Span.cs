using System.Text;

namespace Text
{
    public class TextSpan(int startingIndex, int startingColumn, int endingIndex, int endingColumn)
    {
        public int StartingIndex { get; } = startingIndex;
        public int StartingColumn { get; } = startingColumn;
        public int EndingIndex { get; } = endingIndex;
        public int EndingColumn { get; } = endingColumn;

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
                return document.Lines[StartingIndex][StartingColumn..EndingColumn];
            }

            string content = document.Lines[StartingIndex][StartingColumn..];
            content += Environment.NewLine;
            content += string.Join(Environment.NewLine, document.Lines[(StartingIndex + 1)..EndingIndex]);
            content += document.Lines[EndingIndex][..EndingColumn];
            return content;
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
            if (StartingIndex == EndingIndex)
            {
                document.Lines[StartingIndex] = string.Concat(document.Lines[StartingIndex][StartingColumn..], string.Join(Environment.NewLine, content), document.Lines[StartingIndex][..EndingColumn]);
            }
            else
            {
                StringBuilder sb = new StringBuilder();
                sb.Append(document.Lines[StartingIndex][StartingColumn..]);
                sb.Append(content[0]);

                document.Lines[StartingIndex] = document.Lines[StartingIndex][..StartingColumn] + content[0];

                for (int i = StartingIndex + 1; i < EndingIndex; i++)
                {
                    document.Lines.RemoveAt(StartingIndex + 1);
                    offset--;
                }

                // Skip the first line, since it was already updated.
                for (int i = 1; i < content.Length; i++)
                {
                    document.Lines.Insert(StartingIndex + i + 1, content[i]);
                    offset++;
                }

                if (content.Length > 1)
                {
                    document.Lines[EndingIndex] = content[^1] + document.Lines[EndingIndex + offset][EndingColumn..];
                }
                else
                {
                    document.Lines[EndingIndex] = document.Lines[EndingIndex][EndingColumn..];

                }
            }

            return offset;
        }

        public void RemoveContent(TextDocument document)
        {
            SetContent(document, []);
        }
    }
}
