// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using LanguageExt;
using NLog;

namespace Compiler.Text.Updater;

public class ExactUpdater : TextSpanUpdater {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private readonly Func<string[], string[]> Updater;

    private readonly UpdateOptions UpdateOptions;

    public TextSpan Span;

    /// <summary>
    /// Creates a new <see cref="ExactUpdater"/> instance.
    /// </summary>
    /// <param name="priority"></param>
    /// <param name="startingIndex"></param>
    /// <param name="startingColumn"></param>
    /// <param name="endingIndex"></param>
    /// <param name="endingColumn"></param>
    /// <param name="options"></param>
    /// <param name="updater"></param>
    /// <exception cref="ArgumentException">
    /// Thrown if the starting column is greater than the ending column and the starting index is the same as the ending index.
    /// </exception>
    public ExactUpdater(
        [NotNull] uint priority,
        [NotNull] int startingIndex,
        [NotNull] int startingColumn,
        [NotNull] int endingIndex,
        [NotNull] int endingColumn,
        [NotNull] UpdateOptions options,
        [NotNull] Func<string[], string[]> updater
    ) : base(priority) {
        this.Updater = updater;
        this.UpdateOptions = options;
        this.Span = TextSpan.New(startingIndex, startingColumn, endingIndex, endingColumn).ThrowIfFail();

        if (this.Span.StartingIndex == this.Span.EndingIndex && this.Span.StartingColumn > this.Span.EndingColumn) {
            throw new ArgumentException($"Starting column must be less than ending column, got {this.Span.StartingColumn} and {this.Span.EndingColumn}.");
        }
    }

    public override Fin<SpanUpdateInfo[]> Apply([NotNull] List<string> lines) => lines.AsOption()
        .FailIf(
            l => l.Count - 1 < this.Span.StartingIndex || this.Span.EndingIndex > l.Count - 1,
            l => Error.New($"Span indexes must be within the bounds of the document ({l.Count}), got {this.Span.StartingIndex} and {this.Span.EndingIndex}."))
        .FailIfOpt(
            l => this.Span.StartingIndex > this.Span.EndingIndex,
            l => Error.New($"Starting index must be less than ending index, got {this.Span.StartingIndex} and {this.Span.EndingIndex}."))
         .FailIfOpt(
            l => this.Span.StartingColumn > l[this.Span.StartingIndex].Length,
            l => Error.New($"Starting column must be less than the length of the line ({l[this.Span.StartingIndex].Length - 1}), got index {this.Span.StartingColumn}.")
        )
        .FailIfOpt(
            l => this.Span.EndingColumn > l[this.Span.EndingIndex].Length,
            l => Error.New($"Ending column must be less than the length of the line ({l[this.Span.EndingIndex].Length - 1}), got index {this.Span.EndingColumn}.")
        )
        .AndThen(opt => opt.UnwrapOr([]))
        .AndThen<List<string>, SpanUpdateInfo[]>(lines => {
            string[] newLines;
            int offset;
            if (this.Span.StartingIndex == this.Span.EndingIndex) {
                var updatingLine = lines[this.Span.StartingIndex][this.Span.StartingColumn..this.Span.EndingColumn];
                newLines = this.Updater([updatingLine]);
                offset = this.Span.SetContent(lines, this.UpdateOptions, newLines);
            } else {
                var updatingLines = lines.Skip(this.Span.StartingIndex).Take(this.Span.EndingIndex - this.Span.StartingIndex + 1).ToArray();
                // Trim the starting and ending lines to the correct columns.
                updatingLines[0] = lines[this.Span.StartingIndex][this.Span.StartingColumn..];
                updatingLines[^1] = lines[this.Span.EndingIndex][..this.Span.EndingColumn];

                newLines = this.Updater(updatingLines);
                offset = this.Span.SetContent(lines, this.UpdateOptions, newLines);
            }

            return [new SpanUpdateInfo(this.Span, offset)];
        });

    public override void PushByUpdate(SpanUpdateInfo updateInfo) {
        if (this.Span.StartingIndex >= updateInfo.TextSpan.StartingIndex) {
            this.Span = this.Span with {
                StartingIndex = this.Span.StartingIndex + updateInfo.Offset
            };
        }

        if (this.Span.EndingIndex >= updateInfo.TextSpan.StartingIndex) {
            this.Span = this.Span with {
                EndingIndex = this.Span.EndingIndex + updateInfo.Offset
            };
        }
    }

    public override string ToString() =>
        $"{nameof(ExactUpdater)}({this.Span.StartingIndex}[{this.Span.StartingColumn}..]..{this.Span.EndingIndex}[..{this.Span.EndingColumn}])";
}
