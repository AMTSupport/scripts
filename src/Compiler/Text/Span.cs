// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics;
using System.Diagnostics.CodeAnalysis;
using System.Diagnostics.Contracts;
using System.Globalization;
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

public sealed record ContentChange(
    int LineOffset,
    int StartingColumnOffset,
    int EndingColumnOffset
);

public sealed record TextSpan : IComparable<TextSpan> {
    /// <summary>
    /// An empty span that contains no content and has no updates.
    /// </summary>
    public static readonly TextSpan Empty = new(0, 0, 0, 0);

    [NotNull, JetBrains.Annotations.NonNegativeValue]
    public int StartingIndex { get; init; }
    [NotNull, JetBrains.Annotations.NonNegativeValue]
    public int StartingColumn { get; init; }
    [NotNull, JetBrains.Annotations.NonNegativeValue]
    public int EndingIndex { get; init; }
    [NotNull, JetBrains.Annotations.NonNegativeValue]
    public int EndingColumn { get; init; }

    /// <summary>
    /// Provides a list of updates that have been applied to the span, in order of application.
    /// </summary>
    private IEnumerable<SpanUpdateInfo> AppliedUpdates { get; init; } = [];

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

    [Pure]
    [return: NotNull]
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

    [Pure]
    [return: NotNull]
    public bool Contains([NotNull] TextSpan span) {
        if (span.StartingIndex < this.StartingIndex || span.EndingIndex > this.EndingIndex) {
            return false;
        }

        if (span.StartingIndex == this.StartingIndex && span.StartingColumn < this.StartingColumn) {
            return false;
        }

        if (span.EndingIndex == this.EndingIndex && span.EndingColumn > this.EndingColumn) {
            return false;
        }

        return true;
    }

    /// <summary>
    /// Determines if the span overlaps either the starting or end of the span,
    /// but does not contain the entire span.
    /// </summary>
    /// <param name="span"></param>
    /// <returns></returns>
    public bool OverlapsNotContained(TextSpan span) {
        var overlapping = false;
        if (span.StartingIndex == this.StartingIndex) {
            overlapping = span.StartingColumn < this.EndingColumn;
        } else if (span.EndingIndex == this.EndingIndex) {
            overlapping = span.EndingColumn > this.StartingColumn;
        }

        return overlapping;
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
    public Fin<ContentChange> SetContent(
        [NotNull] List<string> lines,
        [NotNull] UpdateOptions options,
        [NotNull] string[] content
    ) {
        if (this.StartingIndex < 0 || this.StartingIndex >= lines.Count) {
            return Error.New($"Starting index {this.StartingIndex} is out of range for document with {lines.Count} lines");
        }

        if (this.EndingIndex < 0 || this.EndingIndex >= lines.Count) {
            return Error.New($"Ending index {this.EndingIndex} is out of range for document with {lines.Count} lines");
        }

        if (this.StartingIndex > this.EndingIndex) {
            return Error.New($"Starting index {this.StartingIndex} is greater than ending index {this.EndingIndex}");
        }

        if (this.StartingIndex == this.EndingIndex && this.StartingColumn > this.EndingColumn) {
            return Error.New($"Starting column {this.StartingColumn} is greater than ending column {this.EndingColumn} on the same line");
        }

        var startingLine = lines[this.StartingIndex];
        if (startingLine.Length < this.StartingColumn) {
            return Error.New($"Starting column {this.StartingColumn} is out of range for line with {startingLine.Length} characters. Line: {startingLine}");
        }

        var endingLine = lines[this.EndingIndex];
        if (endingLine.Length < this.EndingColumn) {
            return Error.New($"Ending column {this.EndingColumn} is out of range for line with {endingLine.Length} characters. Line: {endingLine}");
        }

        var firstLineBefore = startingLine[..this.StartingColumn];
        var lastLineAfter = endingLine[this.EndingColumn..];
        var startingColumnOffset = -firstLineBefore?.Length ?? 0;
        var endingColumnOffset = -(this.EndingColumn + (lastLineAfter?.Length ?? 0));
        var lineOffset = 0;

        if (this.StartingIndex == this.EndingIndex) {
            lines.RemoveAt(this.StartingIndex);
            lineOffset--;
        } else {
            // Remove all lines in the span to get a clean slate.
            for (var i = this.StartingIndex; i <= this.EndingIndex; i++) {
                lines.RemoveAt(this.StartingIndex);
                lineOffset--;
            }
        }

        // Short circuit if the new content is empty, there will be no need to update the document.
        if (string.IsNullOrEmpty(firstLineBefore) && string.IsNullOrEmpty(lastLineAfter) && content.Length == 0) {
            return new ContentChange(lineOffset, startingColumnOffset, endingColumnOffset);
        }

        if (options.HasFlag(UpdateOptions.InsertInline)) {
            var lineContent = new StringBuilder();

            if (!string.IsNullOrEmpty(firstLineBefore)) {
                lineContent.Append(firstLineBefore);
                startingColumnOffset += firstLineBefore.Length;

                if (this.StartingIndex == this.EndingIndex) {
                    endingColumnOffset += firstLineBefore.Length;
                }
            }

            if (content.Length > 0) {
                var firstLineContent = content[0];
                lineContent.Append(firstLineContent);

                if (content.Length > 1) {
                    lines.InsertRange(this.StartingIndex, content.Skip(1));
                    lineOffset += content.Length - 1;
                    endingColumnOffset += content[^1].Length;
                } else if (this.StartingIndex == this.EndingIndex) {
                    endingColumnOffset += firstLineContent.Length;
                }
            }

            if (!string.IsNullOrEmpty(lastLineAfter)) {
                if (this.StartingIndex != this.EndingIndex || content.Length > 1) {
                    lines[this.EndingIndex + lineOffset] += lastLineAfter;
                    endingColumnOffset += lastLineAfter.Length;
                } else {
                    lineContent.Append(lastLineAfter);
                    endingColumnOffset += lastLineAfter.Length;
                }
            }

            lines.Insert(this.StartingIndex, lineContent.ToString());
            lineOffset++;

            if (this.StartingIndex == this.EndingIndex) {
                endingColumnOffset += startingColumnOffset;
            }
        } else {
            var insertingAfterStartingIndex = false;
            if (!string.IsNullOrEmpty(firstLineBefore)) {
                lines.Insert(this.StartingIndex, firstLineBefore);
                insertingAfterStartingIndex = true;
                lineOffset++;
                startingColumnOffset += firstLineBefore.Length;
                if (this.StartingIndex == this.EndingIndex && content.Length == 0) {
                    endingColumnOffset += firstLineBefore.Length;
                }
            }

            if (content.Length > 0) {
                lines.InsertRange(this.StartingIndex + (insertingAfterStartingIndex ? 1 : 0), content);
                lineOffset += content.Length;
            }

            if (!string.IsNullOrEmpty(lastLineAfter)) {
                lines.Insert(this.EndingIndex + lineOffset + 1, lastLineAfter);
                endingColumnOffset += lastLineAfter.Length;
                lineOffset++;
            } else if (content.Length > 0) {
                endingColumnOffset += content[^1].Length;
            }
        }

        return new ContentChange(lineOffset, startingColumnOffset, endingColumnOffset);
    }

    public Fin<ContentChange> RemoveContent(List<string> lines) => this.SetContent(lines, UpdateOptions.None, []);

    [Pure]
    [return: NotNull]
    public TextSpan WithUpdate(params IEnumerable<SpanUpdateInfo> updateInfo) {
        ArgumentNullException.ThrowIfNull(updateInfo);

        if (!updateInfo.Any()) return this;

        var startingIndex = this.StartingIndex;
        var endingIndex = this.EndingIndex;
        var startingColumn = this.StartingColumn;
        var endingColumn = this.EndingColumn;
        foreach (var info in updateInfo) {
            if (info.TextSpan.StartingIndex <= this.StartingIndex) {
                startingIndex += info.Change.LineOffset;
                if (info.TextSpan.StartingIndex == this.StartingIndex) {
                    if (info.TextSpan.StartingColumn <= this.StartingColumn) {
                        startingColumn = Math.Max(0, startingColumn + info.Change.StartingColumnOffset);
                    }
                }
            }


            if (info.TextSpan.StartingIndex <= this.EndingIndex) {
                endingIndex += info.Change.LineOffset;
            }

            if (info.TextSpan.StartingIndex == this.EndingIndex && info.TextSpan.StartingColumn <= this.EndingColumn) {
                endingColumn = Math.Max(0, endingColumn + info.Change.StartingColumnOffset);
            } else if (info.TextSpan.EndingIndex == this.EndingIndex) {
                if ((info.TextSpan.EndingColumn + info.Change.EndingColumnOffset) <= this.EndingColumn) {
                    endingColumn = Math.Max(0, endingColumn + info.Change.EndingColumnOffset);
                }
            }
        }

        return this with {
            StartingIndex = startingIndex,
            EndingIndex = endingIndex,
            StartingColumn = startingColumn,
            EndingColumn = endingColumn
        };

        // var startingIndexOffset = updateInfo.Where(
        //     info => info.TextSpan.StartingIndex <= this.StartingIndex
        // ).Sum(info => info.LineOffset);
        // var endingIndexOffset = updateInfo.Where(
        //     info => info.TextSpan.StartingIndex <= this.EndingIndex
        // ).Sum(info => info.LineOffset);

        // var newStartingIndex = this.StartingIndex + startingIndexOffset;
        // var newEndingIndex = this.EndingIndex + endingIndexOffset;
        // var newAppliedUpdates = this.AppliedUpdates.Concat(updateInfo);

        // return this with {
        //     StartingIndex = newStartingIndex,
        //     EndingIndex = newEndingIndex,
        //     AppliedUpdates = newAppliedUpdates
        // };
    }

    public string StringifyOffset(
        ContentChange change
    ) => $"(({this.StartingIndex} + {change.LineOffset})[({this.StartingColumn} + {change.StartingColumnOffset})..])..(({this.EndingIndex} + {change.LineOffset})[{this.EndingColumn} + {change.EndingColumnOffset}])";

    public override string ToString() {
        var caller = new StackFrame(2).GetMethod();
        var sb = new StringBuilder().Append(CultureInfo.InvariantCulture, $"({this.StartingIndex}[{this.StartingColumn}])..({this.EndingIndex}[{this.EndingColumn}])");

        var originalStartingIndex = this.StartingIndex;
        var originalEndingIndex = this.EndingIndex;

        // If the caller is this ToString method, return a simple string representation, otherwise include the applied updates.
        var skipListingUpdates = caller?.DeclaringType != typeof(SpanUpdateInfo);
        if (this.AppliedUpdates.Any()) {
            if (!skipListingUpdates) {
                sb.Append(CultureInfo.InvariantCulture, $" with {this.AppliedUpdates.Count()} applied updates");
            }

            foreach (var update in this.AppliedUpdates) {
                if (!skipListingUpdates) {
                    sb.Append(CultureInfo.InvariantCulture, $"\n\t{update}");
                }
            }
        }

        return sb.ToString();
    }


    /// <summary>
    /// Spans that are contained within other spans are first,
    /// If they overlap, the span that starts first is first,
    /// If they start at the same index and column, the span that ends first is first.
    /// </summary>
    public int CompareTo(TextSpan? other) {
        if (ReferenceEquals(this, other) || this.Equals(other)) return 0;
        if (other is null) return 1;

        if (this.Contains(other)) return 1;
        if (other.Contains(this)) return -1;

        if (this.StartingIndex != other.StartingIndex) return this.StartingIndex.CompareTo(other.StartingIndex);
        if (this.StartingColumn != other.StartingColumn) return this.StartingColumn.CompareTo(other.StartingColumn);
        if (this.EndingIndex != other.EndingIndex) return this.EndingIndex.CompareTo(other.EndingIndex);
        if (this.EndingColumn != other.EndingColumn) return this.EndingColumn.CompareTo(other.EndingColumn);

        if (this.OverlapsNotContained(other)) return -1;
        if (other.OverlapsNotContained(this)) return 1;

        return 0;
    }

    public override int GetHashCode() => HashCode.Combine(this.StartingIndex, this.StartingColumn, this.EndingIndex, this.EndingColumn);

    public static bool operator <(TextSpan left, TextSpan right) => left is null ? right is not null : left.CompareTo(right) < 0;

    public static bool operator <=(TextSpan left, TextSpan right) => left is null || left.CompareTo(right) <= 0;

    public static bool operator >(TextSpan left, TextSpan right) => left is not null && left.CompareTo(right) > 0;

    public static bool operator >=(TextSpan left, TextSpan right) => left is null ? right is null : left.CompareTo(right) >= 0;
}
