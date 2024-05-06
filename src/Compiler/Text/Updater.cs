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

                var updatingLines = document.Lines.Skip(startIndex).Take(endIndex - startIndex + 1).ToArray();
                var newLines = Updater(updatingLines);

                var thisOffset = newLines.Length - updatingLines.Length;
                offset += thisOffset;
                document.Lines = document.Lines.Take(startIndex).Concat(newLines).Concat(document.Lines.Skip(endIndex + 1)).ToList();
                skipRanges.Add(new Range(startIndex, endIndex));
                spanUpdateInfo.Add(new SpanUpdateInfo(new TextSpan(startIndex, 0, endIndex, 0), thisOffset));
            }

            return [.. spanUpdateInfo];
        }

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
        Regex pattern,
        Func<Match, string> updater
    ) : TextSpanUpdater
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

        public Func<Match, string> Updater { get; } = updater;
        public Regex Pattern { get; } = pattern;

        override public SpanUpdateInfo[] Apply(TextDocument document)
        {
            var spanUpdateInfo = new List<SpanUpdateInfo>();
            var offset = 0;

            var patternString = Pattern.ToString();
            if (patternString.StartsWith("^") && patternString.EndsWith("$"))
            {
                var multilinedContent = string.Join(Environment.NewLine, document.Lines);
                var matches = Pattern.Matches(multilinedContent);
            }
            else
            {
                for (int i = 0; i < document.Lines.Count; i++)
                {
                    var matches = Pattern.Matches(document.Lines[i]);
                    if (matches.Count == 0)
                    {
                        continue;
                    }

                    var thisOffset = 0;
                    foreach (Match match in matches)
                    {
                        var span = new TextSpan(
                            i,
                            match.Index,
                            i,
                            match.Index + match.Length
                        );

                        var isMultiLine = match.Value.Contains(Environment.NewLine);
                        var newContent = Updater(match);

                        // Remove the entire line if the replacement is empty and the match is the entire line.
                        if (string.IsNullOrEmpty(newContent) && match.Index == 0 && match.Length == document.Lines[i].Length)
                        {
                            span.RemoveContent(document);
                            thisOffset--;
                        }
                        else
                        {
                            span.SetContent(document, [newContent]);
                            if (isMultiLine)
                            {
                                thisOffset += newContent.Split(Environment.NewLine).Length - 1;
                            }
                        }

                        spanUpdateInfo.Add(new SpanUpdateInfo(new(
                            i,
                            match.Index,
                            i,
                            match.Index + match.Length
                        ), thisOffset));

                        offset += thisOffset;
                    }
                }
            }

            return [.. spanUpdateInfo];
        }

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

            if (Span.StartingIndex >= Span.EndingIndex)
            {
                Logger.Error($"Starting index must be less than ending index, got {Span.StartingIndex} and {Span.EndingIndex}.");
                return [];
            }

            if (Span.StartingIndex == Span.EndingIndex && Span.StartingColumn >= Span.EndingColumn)
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
                case var (start, _) when Span.StartingColumn >= start.Length:
                    Logger.Error($"Starting column must be less than the length of the line, got index {Span.StartingColumn} for length {start.Length}.");
                    return [];
                case var (_, end) when Span.EndingColumn >= end.Length:
                    Logger.Error($"Ending column must be less than the length of the line, got index {Span.EndingColumn} for length {end.Length}.");
                    return [];
                case var _ when Span.StartingIndex == Span.EndingIndex && Span.StartingColumn >= Span.EndingColumn:
                    Logger.Error($"Starting column must be less than ending column, got index {Span.StartingColumn} for length {Span.EndingColumn}.");
                    return [];
            }

            string[] newLines;
            int offset;
            if (Span.StartingIndex == Span.EndingIndex)
            {
                var updatingLine = document.Lines[Span.StartingIndex][Span.StartingColumn..Span.EndingColumn];
                newLines = Updater([updatingLine]);
                offset = Span.SetContent(document, newLines);
            }
            else
            {
                var updatingLines = document.Lines.Skip(Span.StartingIndex).Take(Span.EndingIndex - Span.StartingIndex + 1).ToArray();
                updatingLines[0] = document.Lines[Span.StartingIndex][Span.StartingColumn..];
                updatingLines[^1] = document.Lines[Span.EndingIndex][..Span.EndingColumn];

                newLines = Updater(updatingLines);
                offset = Span.SetContent(document, newLines);
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
