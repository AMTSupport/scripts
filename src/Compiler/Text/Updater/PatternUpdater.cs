// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.Contracts;
using System.Text;
using System.Text.RegularExpressions;
using CommandLine;
using LanguageExt;
using NLog;

namespace Compiler.Text.Updater;

public class PatternUpdater(
    uint priority,
    Regex startingPattern,
    Regex endingPattern,
    UpdateOptions options,
    Func<string[], string[]> updater
) : TextSpanUpdater(priority) {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public Func<string[], string[]> Updater { get; } = updater;
    public Regex StartingPattern { get; } = startingPattern;
    public Regex EndingPattern { get; } = endingPattern;

    public override Fin<IEnumerable<SpanUpdateInfo>> Apply(List<string> lines) {
        var spanUpdateInfo = new List<SpanUpdateInfo>();
        var skipSpans = new List<TextSpan>();

        while (true) {
            var spanResult = this.FindStartToEndBlock(ref lines, ref skipSpans);
            if (!spanResult.IsSome(out var span)) break;

            var updatingLines = span.GetContent([.. lines]).Split('\n');
            var newLines = this.Updater(updatingLines);
            var thisChange = span.SetContent(lines, options, newLines);
            if (thisChange.IsErr(out var err, out var change)) return err;

            var thisUpdateInfo = new SpanUpdateInfo(this, span, change);
            // Include self for updating because we want its new span location.
            skipSpans.Add(span);
            skipSpans = new List<TextSpan>(skipSpans.Select(s => s.WithUpdate(thisUpdateInfo)));
            spanUpdateInfo.Add(thisUpdateInfo);
        }

        return spanUpdateInfo;
    }

    [Pure]
    private Option<TextSpan> FindStartToEndBlock(
        ref List<string> lines,
        ref List<TextSpan> skipSpans
    ) {
        if (lines == null || lines.Count == 0) return None;

        var startIndex = -1;
        var endIndex = -1;
        var openLevel = 0;

        for (var i = 0; i < lines.Count; i++) {
            var clonedLine = lines[i].Clone().Cast<string>()!;
            // TODO - Actually account for columns instead of just entire rows.
            if (skipSpans.Any(span => span.Contains(i, 0) || span.Contains(i, clonedLine.Length))) continue;

            var openingMatch = this.StartingPattern.Matches(clonedLine);
            if (openingMatch.Count > 0) {
                if (openLevel == 0) {
                    startIndex = i;
                }

                openLevel += openingMatch.Count;
            }

            // If we found at least one startPattern we will want to remove them from the string,
            // This is so that the endingPattern does not match the same elements, and we can find the correct end.
            if (openingMatch.Count > 0) {
                var lineOffset = 0;
                foreach (Match match in openingMatch) {
                    clonedLine = new StringBuilder()
                        .Append(clonedLine[..(match.Index + lineOffset)])
                        .Append(clonedLine[(match.Index + lineOffset + match.Length)..])
                        .ToString();
                    lineOffset -= match.Length;
                }
            }

            if (openLevel > 0) {
                var closingMatch = this.EndingPattern.Matches(clonedLine);
                if (closingMatch.Count > 0) {
                    openLevel -= closingMatch.Count;

                    if (openLevel == 0) {
                        endIndex = i;
                        break;
                    }
                }
            }
        }

        return startIndex == -1 || endIndex == -1
            ? None
            : TextSpan.New(startIndex, 0, endIndex, lines[endIndex].Length).Unwrap();
    }

    public override string ToString() => $"{nameof(PatternUpdater)}[{this.Priority}]->({this.StartingPattern}..{this.EndingPattern})";
}
