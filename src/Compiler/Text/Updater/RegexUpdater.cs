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
    public override Fin<IEnumerable<SpanUpdateInfo>> Apply([NotNull] List<string> lines) {
        var multilinedContent = string.Join('\n', lines);
        var matches = this.Pattern.Matches(multilinedContent);
        if (matches.Count == 0) return System.Array.Empty<SpanUpdateInfo>();

        var offset = 0;
        var spanUpdateInfo = new List<SpanUpdateInfo>();
        foreach (Match match in matches) {
            Fin<ContentChange> thisChange;
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

            // Remove the entire line if the replacement is empty and the match is the entire line.
            if (newContent == null && startingColumn == 0 && match.Length == lines[startingLineIndex].Length) {
                thisChange = span.RemoveContent(lines);
            } else {
                var newLines = newContent == null ? [] : isMultiLine ? newContent.Split('\n') : [newContent];
                thisChange = span.SetContent(lines, options, newLines);
            }

            if (thisChange.IsErr(out var changeError, out var change)) return changeError;

            spanUpdateInfo.Add(new SpanUpdateInfo(this, span, change));
            offset += change.LineOffset;
        }

        return spanUpdateInfo;
    }

    public override string ToString() => $"{nameof(RegexUpdater)}[{this.Priority}]->({this.Pattern})";
}
