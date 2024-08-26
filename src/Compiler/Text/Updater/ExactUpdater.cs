// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using NLog;

namespace Compiler.Text.Updater;

public class ExactUpdater(
    uint priority,
    int startingIndex,
    int startingColumn,
    int endingIndex,
    int endingColumn,
    UpdateOptions options,
    Func<string[], string[]> updater
) : TextSpanUpdater(priority) {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public Func<string[], string[]> Updater = updater;
    public TextSpan Span { get; } = new TextSpan(startingIndex, startingColumn, endingIndex, endingColumn);

    public override SpanUpdateInfo[] Apply([NotNull] ref List<string> lines) {
        ArgumentNullException.ThrowIfNull(lines);

        if (this.Span.StartingIndex < 0 || this.Span.EndingIndex >= lines.Count) {
            return [];
        }

        if (this.Span.StartingIndex > this.Span.EndingIndex) {
            Logger.Error($"Starting index must be less than ending index, got {this.Span.StartingIndex} and {this.Span.EndingIndex}.");
            return [];
        }

        if (this.Span.StartingIndex == this.Span.EndingIndex && this.Span.StartingColumn > this.Span.EndingColumn) {
            Logger.Error($"Starting column must be less than ending column, got {this.Span.StartingColumn} and {this.Span.EndingColumn}.");
            return [];
        }

        switch (lines) {
            case var l when l.Count == 0:
                Logger.Error("Document lines must not be null.");
                return [];
            case var l when l.Count <= this.Span.StartingIndex:
                Logger.Error($"Starting index must be less than the number of lines, got index {this.Span.StartingIndex} for length {l.Count}.");
                return [];
            case var l when l.Count <= this.Span.EndingIndex:
                Logger.Error($"Ending index must be less than the number of lines, got index {this.Span.EndingIndex} for length {l.Count}.");
                return [];
        }

        var startingLine = lines[this.Span.StartingIndex];
        var endingLine = lines[this.Span.EndingIndex];
        switch ((startingLine, endingLine)) {
            case var (start, _) when this.Span.StartingColumn > start.Length:
                Logger.Error($"Starting column must be less than the length of the line, got index {this.Span.StartingColumn} for length {start.Length}.");
                return [];
            case var (_, end) when this.Span.EndingColumn > end.Length:
                Logger.Error($"Ending column must be less than the length of the line, got index {this.Span.EndingColumn} for length {end.Length}.");
                return [];
            case var _ when this.Span.StartingIndex == this.Span.EndingIndex && this.Span.StartingColumn > this.Span.EndingColumn:
                Logger.Error($"Starting column must be less than ending column, got index {this.Span.StartingColumn} for length {this.Span.EndingColumn}.");
                return [];
        }

        string[] newLines;
        int offset;
        if (this.Span.StartingIndex == this.Span.EndingIndex) {
            var updatingLine = lines[this.Span.StartingIndex][this.Span.StartingColumn..this.Span.EndingColumn];
            newLines = this.Updater([updatingLine]);
            offset = this.Span.SetContent(ref lines, options, newLines);
        } else {
            var updatingLines = lines.Skip(this.Span.StartingIndex).Take(this.Span.EndingIndex - this.Span.StartingIndex + 1).ToArray();
            // Trim the starting and ending lines to the correct columns.
            updatingLines[0] = lines[this.Span.StartingIndex][this.Span.StartingColumn..];
            updatingLines[^1] = lines[this.Span.EndingIndex][..this.Span.EndingColumn];

            newLines = this.Updater(updatingLines);
            offset = this.Span.SetContent(ref lines, options, newLines);
        }

        return [new SpanUpdateInfo(this.Span, offset)];
    }

    public override void PushByUpdate(SpanUpdateInfo updateInfo) {
        if (this.Span.StartingIndex >= updateInfo.TextSpan.StartingIndex) {
            this.Span.StartingIndex += updateInfo.Offset;
        }

        if (this.Span.EndingIndex >= updateInfo.TextSpan.StartingIndex) {
            this.Span.EndingIndex += updateInfo.Offset;
        }
    }

    public override string ToString() => $"{nameof(ExactUpdater)}({startingIndex}[{startingColumn}..]..{endingIndex}[..{endingColumn}])";
}
