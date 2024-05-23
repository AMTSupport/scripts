using System.Management.Automation;
using System.Text;
using JetBrains.Annotations;
using Text.Updater;

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
        public int SetContent(TextDocument document, UpdateOptions options, string[] content)
        {
            var offset = 0;
            var firstLineBefore = document.Lines[StartingIndex][..StartingColumn];
            var lastLineAfter = document.Lines[EndingIndex][EndingColumn..];

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
                    if (StartingIndex != EndingIndex)
                    {
                        document.Lines.Insert(StartingIndex + content.Length, lastLineAfter);
                        offset++;
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

            // if (content.Length == 0)
            // {
            // if (!string.IsNullOrEmpty(firstLineBefore))
            // {
            //     document.Lines.Insert(StartingIndex, firstLineBefore);
            //     offset++;
            // }

            // if (!string.IsNullOrEmpty(lastLineAfter))
            // {
            //     document.Lines.Insert(EndingIndex + offset, lastLineAfter);
            //     offset++;
            // }
            // }
            // else if (content.Length == 1)
            // {
            //     if (StartingIndex == EndingIndex)
            //     {
            //         if (options.HasFlag(UpdateOptions.InsertInline))
            //         {
            //             document.Lines.Insert(StartingIndex, firstLineBefore + content[0] + lastLineAfter);
            //             offset++;
            //         }
            //         else
            //         {
            //             if (!string.IsNullOrEmpty(firstLineBefore))
            //             {
            //                 document.Lines.Insert(StartingIndex, firstLineBefore + content[0]);
            //                 offset++;
            //             }

            //             document.Lines.Insert(StartingIndex + 1, content[0]);
            //             offset++;

            //             if (!string.IsNullOrEmpty(lastLineAfter))
            //             {
            //                 document.Lines.Insert(StartingIndex + 2, lastLineAfter);
            //                 offset++;
            //             }
            //         }
            //     }
            //     else
            //     {
            //         document.Lines.Insert(StartingIndex, firstLineBefore + content[0]);
            //         offset++;

            //         if (!string.IsNullOrEmpty(lastLineAfter))
            //         {
            //             document.Lines.Insert(EndingIndex + offset, lastLineAfter);
            //             offset++;
            //         }
            //     }
            // }
            // else
            // {
            //     for (int i = 0; i < content.Length; i++)
            //     {
            //         string lineContent = i switch
            //         {
            //             var index when index == 0 => firstLineBefore + content.First(),
            //             var index when index == content.Length - 1 => content.Last() + lastLineAfter,
            //             _ => content[i],
            //         };
            //         document.Lines.Insert(StartingIndex + i, lineContent);
            //         offset++;
            //     }
            // }

            return offset;
        }

        public int RemoveContent(TextDocument document)
        {
            return SetContent(document, UpdateOptions.None, []);
        }
    }
}
