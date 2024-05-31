using System.Diagnostics.CodeAnalysis;
using System.Diagnostics.Contracts;
using System.Text.RegularExpressions;
using CommandLine;
using NLog;

// TODO :: Ast based updater
namespace Text.Updater
{
    public record SpanUpdateInfo(
        TextSpan TextSpan,
        int Offset
    );

    public abstract class TextSpanUpdater
    {
        /// <summary>
        /// Apply the update to the document.
        /// </summary>
        /// <param name="document">
        /// The document to apply the update to.
        /// </param>
        /// <returns>
        /// The number of lines changed by the update.
        /// </returns>
        public abstract SpanUpdateInfo[] Apply(TextDocument document);

        /// <summary>
        /// Use informaiton from another update to possibly update this ones variables.
        /// This can be used to update the starting index of a span after a previous span has been removed.
        /// </summary>
        public abstract void PushByUpdate(SpanUpdateInfo updateInfo);
    }

    public class PatternUpdater(
        Regex startingPattern,
        Regex endingPattern,
        UpdateOptions options,
        Func<string[], string[]> updater
    ) : TextSpanUpdater
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

        public Func<string[], string[]> Updater { get; } = updater;
        public Regex StartingPattern { get; } = startingPattern;
        public Regex EndingPattern { get; } = endingPattern;

        override public SpanUpdateInfo[] Apply(TextDocument document)
        {
            var spanUpdateInfo = new List<SpanUpdateInfo>();
            var skipRanges = new HashSet<Range>();
            var offset = 0;

            while (true)
            {
                var (startIndex, endIndex) = FindStartToEndBlock([.. document.Lines], offset, skipRanges);
                if (startIndex == -1 || endIndex == -1)
                {
                    break;
                }

                var span = new TextSpan(
                    startIndex,
                    0,
                    endIndex,
                    document.Lines[endIndex].Length
                );

                var updatingLines = document.Lines[startIndex..(endIndex + 1)].ToArray();
                var newLines = Updater(updatingLines);

                var thisOffset = span.SetContent(document, options, Updater(document.Lines.Skip(startIndex).Take(endIndex - startIndex + 1).ToArray()));

                offset += thisOffset;
                skipRanges.Add(new Range(startIndex, endIndex));
                spanUpdateInfo.Add(new SpanUpdateInfo(span, thisOffset));
            }

            return [.. spanUpdateInfo];
        }

        [Pure, ExcludeFromCodeCoverage(Justification = "Does nothing in this context.")]
        public override void PushByUpdate(SpanUpdateInfo updateInfo)
        {
            Logger.Debug($"No need to update pattern updater.");
        }

        private (int, int) FindStartToEndBlock(
            string[] lines,
            int offset,
            HashSet<Range> skipRanges
        )
        {
            if (offset < 0 || offset >= lines.Length || lines.Length == 0)
            {
                return (-1, -1);
            }

            int startIndex = -1;
            int endIndex = -1;
            int openLevel = 0;

            for (int i = offset; i < lines.Length; i++)
            {
                var clonedLine = lines[i].Clone().Cast<string>()!;
                if (skipRanges.Any(range => (range.Start.Value + offset) <= i && (range.End.Value + offset) >= i))
                {
                    continue;
                }

                var openingMatch = StartingPattern.Matches(clonedLine);
                if (openingMatch.Count > 0)
                {
                    if (openLevel == 0)
                    {
                        startIndex = i;
                    }

                    openLevel += openingMatch.Count;
                }

                // If we found at least one startPattern we will want to remove them from the string,
                // This is so that the endingPattern does not match the same elements, and we can find the correct end.
                if (openingMatch.Count > 0)
                {
                    clonedLine = StartingPattern.Replace(clonedLine, "", openingMatch.Count);
                }

                var closingMatch = EndingPattern.Matches(clonedLine);
                if (closingMatch.Count > 0)
                {
                    openLevel -= closingMatch.Count;

                    if (openLevel == 0)
                    {
                        endIndex = i;
                        break;
                    }
                }
            }

            return (startIndex, endIndex);
        }
    }

    public class RegexUpdater(
        string pattern,
        UpdateOptions options,
        Func<Match, string> updater
    ) : TextSpanUpdater
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

        public Func<Match, string> Updater { get; } = updater;
        public Regex Pattern
        {
            get
            {
                if (options.HasFlag(UpdateOptions.MatchEntireDocument))
                {
                    return new Regex(pattern, RegexOptions.Multiline | RegexOptions.Singleline);
                }
                else
                {
                    return new Regex(pattern, RegexOptions.Multiline);
                }
            }
        }

        // TODO - Refactor
        /// <summary>
        /// Applies the specified pattern to the given text document and returns an array of <see cref="SpanUpdateInfo"/> objects.
        /// </summary>
        /// <param name="document">The text document to apply the pattern to.</param>
        /// <returns>An array of <see cref="SpanUpdateInfo"/> objects representing the updates made to the document.</returns>
        override public SpanUpdateInfo[] Apply(TextDocument document)
        {
            var spanUpdateInfo = new List<SpanUpdateInfo>();
            var offset = 0;

            var multilinedContent = string.Join('\n', document.Lines);
            var matches = Pattern.Matches(multilinedContent);

            if (matches.Count == 0)
            {
                return [];
            }

            foreach (Match match in matches)
            {
                var thisOffset = 0;
                var multilineEndingIndex = match.Index + match.Length;
                var contentBeforeThisLine = multilinedContent[..match.Index].LastIndexOf(value: '\n');
                var isMultiLine = options.HasFlag(UpdateOptions.MatchEntireDocument) && match.Value.Contains('\n');
                var startingLineIndex = multilinedContent[..match.Index].Count(c => c == '\n') + offset;
                var endingLineIndex = multilinedContent[..multilineEndingIndex].Count(c => c == '\n') + offset;

                int startingColumn;
                int endingColumn;
                if (isMultiLine)
                {
                    startingColumn = match.Index;
                    // endingColumn = multilineEndingIndex - (contentBeforeThisLine + 1);
                    endingColumn = multilineEndingIndex - (multilinedContent[match.Index..match.Length].LastIndexOf('\n') + 1);
                }
                else
                {
                    startingColumn = match.Index - (contentBeforeThisLine + 1);
                    endingColumn = match.Length;
                }

                var span = new TextSpan(
                    startingLineIndex,
                    startingColumn,
                    endingLineIndex,
                    endingColumn
                );

                var newContent = Updater(match);

                // Remove the entire line if the replacement is empty and the match is the entire line.
                if (string.IsNullOrEmpty(newContent) && startingColumn == 0 && match.Length == document.Lines[startingLineIndex].Length)
                {
                    thisOffset += span.RemoveContent(document);
                }
                else
                {
                    span.SetContent(document, options, [newContent]);
                    if (isMultiLine)
                    {
                        thisOffset += newContent.Split('\n').Length - 1;
                    }
                }

                spanUpdateInfo.Add(new SpanUpdateInfo(span, thisOffset));
                offset += thisOffset;
            }

            return [.. spanUpdateInfo];
        }

        [Pure, ExcludeFromCodeCoverage(Justification = "Does nothing in this context.")]
        public override void PushByUpdate(SpanUpdateInfo updateInfo)
        {
            Logger.Debug($"No need to update regex updater.");
        }
    }

    public class ExactUpdater(
        int startingIndex,
        int startingColumn,
        int endingIndex,
        int endingColumn,
        UpdateOptions options,
        Func<string[], string[]> updater
    ) : TextSpanUpdater
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

        public Func<string[], string[]> Updater = updater;
        public TextSpan Span { get; } = new TextSpan(startingIndex, startingColumn, endingIndex, endingColumn);

        override public SpanUpdateInfo[] Apply(TextDocument document)
        {
            if (Span.StartingIndex < 0 || Span.EndingIndex >= document.Lines.Count)
            {
                return [];
            }

            if (Span.StartingIndex > Span.EndingIndex)
            {
                Logger.Error($"Starting index must be less than ending index, got {Span.StartingIndex} and {Span.EndingIndex}.");
                return [];
            }

            if (Span.StartingIndex == Span.EndingIndex && Span.StartingColumn > Span.EndingColumn)
            {
                Logger.Error($"Starting column must be less than ending column, got {Span.StartingColumn} and {Span.EndingColumn}.");
                return [];
            }

            switch (document)
            {
                case null:
                    Logger.Error("Document must not be null.");
                    return [];
                case var doc when doc.Lines.Count == 0:
                    Logger.Error("Document lines must not be null.");
                    return [];
                case var doc when doc.Lines.Count <= Span.StartingIndex:
                    Logger.Error($"Starting index must be less than the number of lines, got index {Span.StartingIndex} for length {doc.Lines.Count}.");
                    return [];
                case var doc when doc.Lines.Count <= Span.EndingIndex:
                    Logger.Error($"Ending index must be less than the number of lines, got index {Span.EndingIndex} for length {doc.Lines.Count}.");
                    return [];
            }

            var startingLine = document.Lines[Span.StartingIndex];
            var endingLine = document.Lines[Span.EndingIndex];
            switch ((startingLine, endingLine))
            {
                case var (start, _) when Span.StartingColumn > start.Length:
                    Logger.Error($"Starting column must be less than the length of the line, got index {Span.StartingColumn} for length {start.Length}.");
                    return [];
                case var (_, end) when Span.EndingColumn > end.Length:
                    Logger.Error($"Ending column must be less than the length of the line, got index {Span.EndingColumn} for length {end.Length}.");
                    return [];
                case var _ when Span.StartingIndex == Span.EndingIndex && Span.StartingColumn > Span.EndingColumn:
                    Logger.Error($"Starting column must be less than ending column, got index {Span.StartingColumn} for length {Span.EndingColumn}.");
                    return [];
            }

            string[] newLines;
            int offset;
            if (Span.StartingIndex == Span.EndingIndex)
            {
                var updatingLine = document.Lines[Span.StartingIndex][Span.StartingColumn..Span.EndingColumn];
                newLines = Updater([updatingLine]);
                offset = Span.SetContent(document, options, newLines);
            }
            else
            {
                var updatingLines = document.Lines.Skip(Span.StartingIndex).Take(Span.EndingIndex - Span.StartingIndex + 1).ToArray();
                // Trim the starting and ending lines to the correct columns.
                updatingLines[0] = document.Lines[Span.StartingIndex][Span.StartingColumn..];
                updatingLines[^1] = document.Lines[Span.EndingIndex][..Span.EndingColumn];

                newLines = Updater(updatingLines);
                offset = Span.SetContent(document, options, newLines);
            }

            return [new SpanUpdateInfo(Span, offset)];
        }

        override public void PushByUpdate(SpanUpdateInfo updateInfo)
        {
            Logger.Debug($"Pushing by update for exact updater with {updateInfo}.");

            if (Span.StartingIndex >= updateInfo.TextSpan.StartingIndex)
            {
                Logger.Debug($"Updating starting index from {Span.StartingIndex} to {Span.StartingIndex + updateInfo.Offset}.");
                Span.StartingIndex += updateInfo.Offset;
            }

            if (Span.EndingIndex >= updateInfo.TextSpan.StartingIndex)
            {
                Logger.Debug($"Updating ending index from {Span.EndingIndex} to {Span.EndingIndex + updateInfo.Offset}.");
                Span.EndingIndex += updateInfo.Offset;
            }
        }
    }
}
