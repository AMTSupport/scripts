// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using System.Text.RegularExpressions;
using LanguageExt;
using NLog;

namespace Compiler.Text.Updater;

public class RegexUpdater(
    uint priority,
    Regex pattern,
    UpdateOptions options,
    Func<Match, string?> updater
) : TextSpanUpdater(priority) {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public readonly Func<Match, string?> Updater = updater;
    public Regex Pattern {
        get {
            if (options.HasFlag(UpdateOptions.MatchEntireDocument)) {
                return new Regex(pattern.ToString(), pattern.Options | RegexOptions.Multiline | RegexOptions.Singleline);
            } else {
                return new Regex(pattern.ToString(), pattern.Options | RegexOptions.Multiline);
            }
        }
    }

    /// <summary>
    /// Applies the specified pattern to the given text document and returns an array of <see cref="SpanUpdateInfo"/> objects.
    /// </summary>
    /// <param name="document">The text document to apply the pattern to.</param>
    /// <returns>
    /// An array of <see cref="SpanUpdateInfo"/> objects representing the updates made to the document.
    /// </returns>
    [return: NotNull]
    public override Fin<SpanUpdateInfo[]> Apply([NotNull] List<string> lines) {
        ArgumentNullException.ThrowIfNull(lines);

        var multilinedContent = string.Join('\n', lines);
        var matches = this.Pattern.Matches(multilinedContent);

        if (matches.Count == 0) {
            return FinSucc<SpanUpdateInfo[]>([]);
        }

        var spanUpdateInfo = new List<SpanUpdateInfo>();
        var offset = 0;
        foreach (Match match in matches) {
            var thisOffset = 0;
            var multilineEndingIndex = match.Index + match.Length;
            var contentBeforeThisLine = multilinedContent[..match.Index].LastIndexOf(value: '\n');
            var isMultiLine = options.HasFlag(UpdateOptions.MatchEntireDocument) && match.Value.Contains('\n');
            var startingLineIndex = multilinedContent[..match.Index].Count(c => c == '\n') + offset;
            var endingLineIndex = multilinedContent[..multilineEndingIndex].Count(c => c == '\n') + offset;

            int startingColumn;
            int endingColumn;
            startingColumn = match.Index - (contentBeforeThisLine + 1);
            endingColumn = isMultiLine
                ? multilineEndingIndex - (multilinedContent[..multilineEndingIndex].LastIndexOf('\n') + 1)
                : startingColumn + match.Length;

            var spanResult = TextSpan.New(startingLineIndex, startingColumn, endingLineIndex, endingColumn);
            if (spanResult.IsErr(out var spanError, out var span)) {
                return spanError;
            }

            var newContent = this.Updater(match);

            // FIXME These shouldn't happen and are likely a bug in the updater.
            if (startingLineIndex > lines.Count) {
                return FinFail<SpanUpdateInfo[]>(new ArgumentOutOfRangeException(
                    nameof(lines),
                    startingLineIndex,
                    "Starting line index is greater than the number of lines in the document."
                ));
            }
            if (endingLineIndex > lines.Count) {
                return FinFail<SpanUpdateInfo[]>(new ArgumentOutOfRangeException(
                    nameof(lines),
                    endingLineIndex,
                    "Ending line index is greater than the number of lines in the document."
                ));
            }
            if (startingColumn > lines[startingLineIndex].Length) {
                return FinFail<SpanUpdateInfo[]>(new ArgumentOutOfRangeException(
                    nameof(lines),
                    startingColumn,
                    "Starting column is greater than the length of the line."
                ));
            }
            if (endingColumn > lines[endingLineIndex].Length) {
                return FinFail<SpanUpdateInfo[]>(new ArgumentOutOfRangeException(
                    nameof(lines),
                    endingColumn,
                    "Ending column is greater than the length of the line."
                ));
            }
            if (startingLineIndex > endingLineIndex) {
                return FinFail<SpanUpdateInfo[]>(new ArgumentOutOfRangeException(
                    nameof(lines),
                    startingLineIndex,
                    "Starting line index is greater than the ending line index."
                ));
            }
            if (startingLineIndex == endingLineIndex && startingColumn > endingColumn) {
                return FinFail<SpanUpdateInfo[]>(new ArgumentOutOfRangeException(
                    nameof(lines),
                    startingColumn,
                    "Starting column is greater than the ending column."
                ));
            }

            // Remove the entire line if the replacement is empty and the match is the entire line.
            if (newContent == null && startingColumn == 0 && match.Length == lines[startingLineIndex].Length) {
                thisOffset += span.RemoveContent(lines);
            } else {
                var newLines = newContent == null ? [] : isMultiLine ? newContent.Split('\n') : [newContent];
                thisOffset += span.SetContent(lines, options, newLines);
                if (isMultiLine) {
                    thisOffset += newLines.Length - 1;
                }
            }

            spanUpdateInfo.Add(new SpanUpdateInfo(span, thisOffset));
            offset += thisOffset;
        }

        return FinSucc(spanUpdateInfo.ToArray());
    }

    public override string ToString() => $"{nameof(RegexUpdater)}({this.Pattern})";
}
