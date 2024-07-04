using System.Diagnostics.CodeAnalysis;
using System.Management.Automation;
using System.Text;
using JetBrains.Annotations;
using NLog;

namespace Compiler.Text;

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
    [ExcludeFromCodeCoverage(Justification = "Logging")]
    private static Logger Logger { get => LogManager.GetCurrentClassLogger(); }

    [ValidateRange(0, int.MaxValue)] public int StartingIndex = startingIndex;
    [ValidateRange(0, int.MaxValue)] public int StartingColumn = startingColumn;
    [ValidateRange(0, int.MaxValue)] public int EndingIndex = endingIndex;
    [ValidateRange(0, int.MaxValue)] public int EndingColumn = endingColumn;

    public static TextSpan WrappingEntireDocument(TextDocument document) => WrappingEntireDocument([.. document.Lines]);

    public static TextSpan WrappingEntireDocument(string[] lines)
    {
        if (lines.Length == 0)
        {
            return new TextSpan(0, 0, 0, 0);
        }

        return new TextSpan(0, 0, lines.Length - 1, lines[^1].Length);
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

    public string GetContent(TextDocument document) => GetContent([.. document.Lines]);

    [Pure]
    public string GetContent(string[] lines)
    {
        if (lines.Length == 0)
        {
            return string.Empty;
        }

        if (StartingIndex < 0 || StartingIndex >= lines.Length)
        {
            Logger.Error("Starting index {0} is out of range for document with {1} lines", StartingIndex, lines.Length);
            throw new ArgumentOutOfRangeException(nameof(StartingIndex));
        }

        if (StartingIndex == EndingIndex)
        {
            if (StartingColumn == 0 && EndingColumn == lines[StartingIndex].Length)
            {
                return lines[StartingIndex];
            }

            if (StartingColumn == EndingColumn)
            {
                return string.Empty;
            }

            return lines[StartingIndex][StartingColumn..EndingColumn];
        }

        var builder = new StringBuilder();
        builder.Append(lines[StartingIndex][StartingColumn..] + '\n');
        for (int i = StartingIndex + 1; i < EndingIndex; i++)
        {
            builder.Append(lines[i] + '\n');
        }
        builder.Append(lines[EndingIndex][..EndingColumn]);

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
        ref List<string> lines,
        UpdateOptions options,
        string[] content
    )
    {
        if (StartingIndex < 0 || StartingIndex >= lines.Count)
        {
            Logger.Error("Starting index {0} is out of range for document with {1} lines", StartingIndex, lines.Count);
            throw new ArgumentOutOfRangeException(nameof(StartingIndex), $"Starting index {StartingIndex} is out of range for document with {lines.Count} lines");
        }

        if (EndingIndex < 0 || EndingIndex >= lines.Count)
        {
            Logger.Error("Ending index {0} is out of range for document with {1} lines", EndingIndex, lines.Count);
            throw new ArgumentOutOfRangeException(nameof(EndingIndex), $"Ending index {EndingIndex} is out of range for document with {lines.Count} lines");
        }

        if (StartingIndex > EndingIndex)
        {
            Logger.Error("Starting index {0} is greater than ending index {1}", StartingIndex, EndingIndex);
            throw new ArgumentOutOfRangeException(nameof(StartingIndex), $"Starting index {StartingIndex} is greater than ending index {EndingIndex}");
        }

        if (StartingIndex == EndingIndex && StartingColumn > EndingColumn)
        {
            Logger.Error("Starting column {0} is greater than ending column {1} on the same line", StartingColumn, EndingColumn);
            throw new ArgumentOutOfRangeException(nameof(StartingColumn), $"Starting column {StartingColumn} is greater than ending column {EndingColumn} on the same line");
        }

        var startingLine = lines[StartingIndex];
        if (startingLine.Length < StartingColumn)
        {
            Logger.Error("Starting column {0} is out of range for line with {1} characters", StartingColumn, startingLine.Length);
            throw new ArgumentOutOfRangeException(nameof(StartingColumn), $"Starting column {StartingColumn} is out of range for line with {startingLine.Length} characters. Line: {startingLine}");
        }

        var endingLine = lines[EndingIndex];
        if (endingLine.Length < EndingColumn)
        {
            Logger.Error("Ending column {0} is out of range for line with {1} characters", EndingColumn, endingLine.Length);
            throw new ArgumentOutOfRangeException(nameof(EndingColumn), $"Ending column {EndingColumn} is out of range for line with {endingLine.Length} characters. Line: {endingLine}");
        }

        var offset = 0;
        var firstLineBefore = startingLine[..StartingColumn];
        var lastLineAfter = endingLine[EndingColumn..];

        if (StartingIndex == EndingIndex)
        {
            lines.RemoveAt(StartingIndex);
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
                lines.RemoveAt(StartingIndex);
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

                lines.InsertRange(StartingIndex, content.Skip(1));
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
                    lines[EndingIndex + offset] += lastLineAfter;
                }
                else
                {
                    lineContent.Append(lastLineAfter);
                }
            }

            lines.Insert(StartingIndex, lineContent.ToString());
            offset++;
        }
        else
        {
            var insertingAfterStartingIndex = false;
            if (!string.IsNullOrEmpty(firstLineBefore))
            {
                lines.Insert(StartingIndex, firstLineBefore);
                insertingAfterStartingIndex = true;
                offset++;
            }

            if (content.Length > 0)
            {
                lines.InsertRange(StartingIndex + (insertingAfterStartingIndex ? 1 : 0), content);
                offset += content.Length;
            }

            if (!string.IsNullOrEmpty(lastLineAfter))
            {
                lines.Insert(EndingIndex + offset + 1, lastLineAfter);
                offset++;
            }
        }

        return offset;
    }

    public int RemoveContent(ref List<string> lines)
    {
        return SetContent(ref lines, UpdateOptions.None, []);
    }

    public override bool Equals(object? obj)
    {
        if (obj is TextSpan span)
        {
            return span.StartingIndex == StartingIndex &&
                   span.StartingColumn == StartingColumn &&
                   span.EndingIndex == EndingIndex &&
                   span.EndingColumn == EndingColumn;
        }

        return false;
    }

    public override int GetHashCode() => HashCode.Combine(StartingIndex, StartingColumn, EndingIndex, EndingColumn);

    public override string ToString() => $"({StartingIndex}, {StartingColumn}) - ({EndingIndex}, {EndingColumn})";
}
