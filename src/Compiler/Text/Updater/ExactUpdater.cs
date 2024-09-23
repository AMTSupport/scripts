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
            throw new ArgumentException($"Starting column must be less than ending column, got {this.Span.StartingColumn}..{this.Span.EndingColumn}.");
        }
    }

    public override Fin<IEnumerable<SpanUpdateInfo>> Apply([NotNull] List<string> lines) => lines.AsOption()
        .FailIf(
            l => l.Count <= this.Span.StartingIndex || this.Span.EndingIndex >= l.Count,
            l => Error.New($"Span indexes must be within the length of the document ({l.Count}), was {this.Span.StartingIndex}..{this.Span.EndingIndex}."))
        .FailIfOpt(
            l => this.Span.StartingIndex > this.Span.EndingIndex,
            l => Error.New($"Starting index must be less than ending index, was {this.Span.StartingIndex}..{this.Span.EndingIndex}."))
        .FailIfOpt(
            l => this.Span.StartingColumn > l[this.Span.StartingIndex].Length,
            l => Error.New($"Starting column must be less than the length of the line ({l[this.Span.StartingIndex].Length - 1}), got index {this.Span.StartingColumn}.")
        )
        .FailIfOpt(
            l => this.Span.EndingColumn > l[this.Span.EndingIndex].Length,
            l => Error.New($"Ending column must be less than the length of the line ({l[this.Span.EndingIndex].Length - 1}), got index {this.Span.EndingColumn}.")
        )
        .AndThen(opt => opt.UnwrapOr([]))
        .Bind(lines => {
            Fin<ContentChange> change;
            if (this.Span.StartingIndex == this.Span.EndingIndex) {
                var updatingLine = lines[this.Span.StartingIndex][this.Span.StartingColumn..this.Span.EndingColumn];

                change = this.Span.SetContent(lines, this.UpdateOptions, this.Updater([updatingLine]));
            } else {
                var updatingLines = lines.Skip(this.Span.StartingIndex).Take(this.Span.EndingIndex - this.Span.StartingIndex + 1).ToArray();
                // Trim the starting and ending lines to the correct columns.
                updatingLines[0] = lines[this.Span.StartingIndex][this.Span.StartingColumn..];
                updatingLines[^1] = lines[this.Span.EndingIndex][..this.Span.EndingColumn];

                change = this.Span.SetContent(lines, this.UpdateOptions, this.Updater(updatingLines));
            }

            return change.AndThen(c => {
                return new SpanUpdateInfo(this, this.Span, c);
            });
        });

    public override void PushByUpdate(SpanUpdateInfo updateInfo) => this.Span = this.Span.WithUpdate(updateInfo);

    public override string ToString() => $"{nameof(ExactUpdater)}[{this.Priority}]->{this.Span}";

    public override int CompareTo(TextSpanUpdater? other) {
        if (other is null) return -1;
        if (other is not ExactUpdater otherUpdater) return -1;

        return this.Span.CompareTo(otherUpdater.Span);
    }
}
