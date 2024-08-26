// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation;
using System.Text;
using JetBrains.Annotations;
using NLog;

namespace Compiler.Text;

/// <summary>
/// Specifies the options for updating a document.
/// </summary>
[Flags]
public enum UpdateOptions {
    None = 0,
    MatchEntireDocument = 1,
    InsertInline = 2
}

public class TextSpan(
    [NonNegativeValue] int startingIndex,
    [NonNegativeValue] int startingColumn,
    [NonNegativeValue] int endingIndex,
    [NonNegativeValue] int endingColumn
) {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    [ValidateRange(0, int.MaxValue)] public int StartingIndex = startingIndex;
    [ValidateRange(0, int.MaxValue)] public int StartingColumn = startingColumn;
    [ValidateRange(0, int.MaxValue)] public int EndingIndex = endingIndex;
    [ValidateRange(0, int.MaxValue)] public int EndingColumn = endingColumn;

    public static TextSpan WrappingEntireDocument(TextDocument document) => WrappingEntireDocument([.. document.Lines]);

    public static TextSpan WrappingEntireDocument(string[] lines) {
        if (lines.Length == 0) {
            return new TextSpan(0, 0, 0, 0);
        }

        return new TextSpan(0, 0, lines.Length - 1, lines[^1].Length);
    }

    public bool Contains(int index, int column) {
        if (index < this.StartingIndex || index > this.EndingIndex) {
            return false;
        }

        if (index == this.StartingIndex && column < this.StartingColumn) {
            return false;
        }

        if (index == this.EndingIndex && column > this.EndingColumn) {
            return false;
        }

        return true;
    }

    public string GetContent(TextDocument document) => this.GetContent([.. document.Lines]);

    [Pure]
    public string GetContent(string[] lines) {
        if (lines.Length == 0) return string.Empty;

        if (this.StartingIndex < 0 || this.StartingIndex >= lines.Length) {
            throw new ArgumentOutOfRangeException(nameof(lines), $"Starting index {this.StartingIndex} is out of range for document with {lines.Length} lines");
        }

        if (this.StartingIndex == this.EndingIndex) {
            if (this.StartingColumn == 0 && this.EndingColumn == lines[this.StartingIndex].Length) {
                return lines[this.StartingIndex];
            }

            if (this.StartingColumn == this.EndingColumn) {
                return string.Empty;
            }

            return lines[this.StartingIndex][this.StartingColumn..this.EndingColumn];
        }

        var builder = new StringBuilder();
        builder.Append(lines[this.StartingIndex][this.StartingColumn..] + '\n');
        for (var i = this.StartingIndex + 1; i < this.EndingIndex; i++) {
            builder.Append(lines[i] + '\n');
        }
        builder.Append(lines[this.EndingIndex][..this.EndingColumn]);

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
    ) {
        if (this.StartingIndex < 0 || this.StartingIndex >= lines.Count) {
            throw new ArgumentOutOfRangeException(nameof(lines), $"Starting index {this.StartingIndex} is out of range for document with {lines.Count} lines");
        }

        if (this.EndingIndex < 0 || this.EndingIndex >= lines.Count) {
            throw new ArgumentOutOfRangeException(nameof(lines), $"Ending index {this.EndingIndex} is out of range for document with {lines.Count} lines");
        }

        if (this.StartingIndex > this.EndingIndex) {
            throw new ArgumentOutOfRangeException(nameof(lines), $"Starting index {this.StartingIndex} is greater than ending index {this.EndingIndex}");
        }

        if (this.StartingIndex == this.EndingIndex && this.StartingColumn > this.EndingColumn) {
            throw new ArgumentOutOfRangeException(nameof(lines), $"Starting column {this.StartingColumn} is greater than ending column {this.EndingColumn} on the same line");
        }

        var startingLine = lines[this.StartingIndex];
        if (startingLine.Length < this.StartingColumn) {
            throw new ArgumentOutOfRangeException(nameof(lines), $"Starting column {this.StartingColumn} is out of range for line with {startingLine.Length} characters. Line: {startingLine}");
        }

        var endingLine = lines[this.EndingIndex];
        if (endingLine.Length < this.EndingColumn) {
            throw new ArgumentOutOfRangeException(nameof(lines), $"Ending column {this.EndingColumn} is out of range for line with {endingLine.Length} characters. Line: {endingLine}");
        }

        var offset = 0;
        var firstLineBefore = startingLine[..this.StartingColumn];
        var lastLineAfter = endingLine[this.EndingColumn..];

        if (this.StartingIndex == this.EndingIndex) {
            lines.RemoveAt(this.StartingIndex);
            offset--;

            // Short circuit if the new content is empty, there will be no need to update the document.
            if (string.IsNullOrEmpty(firstLineBefore) && string.IsNullOrEmpty(lastLineAfter) && content.Length == 0) {
                return offset;
            }
        } else {
            // Remove all lines in the span to get a clean slate.
            for (var i = this.StartingIndex; i <= this.EndingIndex; i++) {
                lines.RemoveAt(this.StartingIndex);
                offset--;
            }
        }

        if (options.HasFlag(UpdateOptions.InsertInline)) {
            var lineContent = new StringBuilder();

            if (!string.IsNullOrEmpty(firstLineBefore)) {
                lineContent.Append(firstLineBefore);
            }

            if (content.Length > 1) {
                lineContent.Append(content[0]);

                lines.InsertRange(this.StartingIndex, content.Skip(1));
                offset += content.Length - 1;
            } else {
                lineContent.Append(content[0]);
            }

            if (!string.IsNullOrEmpty(lastLineAfter)) {
                if (this.StartingIndex != this.EndingIndex || content.Length > 1) {
                    lines[this.EndingIndex + offset] += lastLineAfter;
                } else {
                    lineContent.Append(lastLineAfter);
                }
            }

            lines.Insert(this.StartingIndex, lineContent.ToString());
            offset++;
        } else {
            var insertingAfterStartingIndex = false;
            if (!string.IsNullOrEmpty(firstLineBefore)) {
                lines.Insert(this.StartingIndex, firstLineBefore);
                insertingAfterStartingIndex = true;
                offset++;
            }

            if (content.Length > 0) {
                lines.InsertRange(this.StartingIndex + (insertingAfterStartingIndex ? 1 : 0), content);
                offset += content.Length;
            }

            if (!string.IsNullOrEmpty(lastLineAfter)) {
                lines.Insert(this.EndingIndex + offset + 1, lastLineAfter);
                offset++;
            }
        }

        return offset;
    }

    public int RemoveContent(ref List<string> lines) => this.SetContent(ref lines, UpdateOptions.None, []);

    public override bool Equals(object? obj) {
        if (obj is TextSpan span) {
            return span.StartingIndex == this.StartingIndex &&
                   span.StartingColumn == this.StartingColumn &&
                   span.EndingIndex == this.EndingIndex &&
                   span.EndingColumn == this.EndingColumn;
        }

        return false;
    }

    public override int GetHashCode() => HashCode.Combine(this.StartingIndex, this.StartingColumn, this.EndingIndex, this.EndingColumn);

    public override string ToString() => $"({this.StartingIndex}, {this.StartingColumn}) - ({this.EndingIndex}, {this.EndingColumn})";
}
