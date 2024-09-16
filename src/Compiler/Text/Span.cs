// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using System.Diagnostics.Contracts;
using System.Text;
using LanguageExt;

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

public record TextSpan {
    [NotNull, JetBrains.Annotations.NonNegativeValue]
    public int StartingIndex { get; init; }
    [NotNull, JetBrains.Annotations.NonNegativeValue]
    public int StartingColumn { get; init; }
    [NotNull, JetBrains.Annotations.NonNegativeValue]
    public int EndingIndex { get; init; }
    [NotNull, JetBrains.Annotations.NonNegativeValue]
    public int EndingColumn { get; init; }

    /// <summary>
    /// Initialises a new instance of the TextSpan class allowing for logical spans of text to be defined.
    /// </summary>
    /// <param name="startingIndex"></param>
    /// <param name="startingColumn"></param>
    /// <param name="endingIndex"></param>
    /// <param name="endingColumn"></param>
    /// <exception cref="ArgumentNullException">
    /// Thrown if any of the parameters are null.
    /// </exception>
    /// <exception cref="ArgumentOutOfRangeException">
    /// Thrown if any of the parameters are negative,
    /// or if the starting index is greater than the ending index,
    /// or if the starting index is equal to the ending index and the starting column is greater than the ending column.
    /// </exception>
    private TextSpan(
        [NotNull, JetBrains.Annotations.NonNegativeValue] int startingIndex,
        [NotNull, JetBrains.Annotations.NonNegativeValue] int startingColumn,
        [NotNull, JetBrains.Annotations.NonNegativeValue] int endingIndex,
        [NotNull, JetBrains.Annotations.NonNegativeValue] int endingColumn
    ) {
        ArgumentNullException.ThrowIfNull(startingIndex);
        ArgumentNullException.ThrowIfNull(startingColumn);
        ArgumentNullException.ThrowIfNull(endingIndex);
        ArgumentNullException.ThrowIfNull(endingColumn);

        ArgumentOutOfRangeException.ThrowIfNegative(startingIndex);
        ArgumentOutOfRangeException.ThrowIfNegative(startingColumn);
        ArgumentOutOfRangeException.ThrowIfNegative(endingIndex);
        ArgumentOutOfRangeException.ThrowIfNegative(endingColumn);

        ArgumentOutOfRangeException.ThrowIfGreaterThan(startingIndex, endingIndex);
        if (startingIndex == endingIndex) ArgumentOutOfRangeException.ThrowIfGreaterThan(startingColumn, endingColumn);

        this.StartingIndex = startingIndex;
        this.StartingColumn = startingColumn;
        this.EndingIndex = endingIndex;
        this.EndingColumn = endingColumn;
    }

    /// <summary>
    /// Creates a new Instance of the TextSpan class, catching any exceptions that may be thrown.
    /// </summary>
    public static Fin<TextSpan> New(
        [NotNull, JetBrains.Annotations.NonNegativeValue] int startingIndex,
        [NotNull, JetBrains.Annotations.NonNegativeValue] int startingColumn,
        [NotNull, JetBrains.Annotations.NonNegativeValue] int endingIndex,
        [NotNull, JetBrains.Annotations.NonNegativeValue] int endingColumn
    ) {
        try {
            return new TextSpan(startingIndex, startingColumn, endingIndex, endingColumn);
        } catch (Exception err) when (err is ArgumentNullException or ArgumentOutOfRangeException) {
            return FinFail<TextSpan>(err);
        }
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

    public string GetContent(TextDocument document) => this.GetContent([.. document.GetLines()]);

    [Pure]
    [return: NotNull]
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
        [NotNull] List<string> lines,
        [NotNull] UpdateOptions options,
        [NotNull] string[] content
    ) {
        ArgumentNullException.ThrowIfNull(lines);
        ArgumentNullException.ThrowIfNull(options);
        ArgumentNullException.ThrowIfNull(content);

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

            if (content.Length > 0) {
                lineContent.Append(content[0]);

                if (content.Length > 1) {
                    lines.InsertRange(this.StartingIndex, content.Skip(1));
                    offset += content.Length - 1;
                }
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

    public int RemoveContent(List<string> lines) => this.SetContent(lines, UpdateOptions.None, []);

    public override int GetHashCode() => HashCode.Combine(this.StartingIndex, this.StartingColumn, this.EndingIndex, this.EndingColumn);

    public override string ToString() => $"({this.StartingIndex}, {this.StartingColumn}) - ({this.EndingIndex}, {this.EndingColumn})";
}
