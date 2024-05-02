using System.Text.RegularExpressions;

namespace Text.Updater
{
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
        public abstract int Apply(TextDocument document);
    }

    public class PatternUpdater(
        Regex startingPattern,
        Regex endingPattern,
        Func<string[], string[]> updater
    ) : TextSpanUpdater
    {
        public Func<string[], string[]> Updater { get; } = updater;
        public Regex StartingPattern { get; } = startingPattern;
        public Regex EndingPattern { get; } = endingPattern;

        override public int Apply(TextDocument document)
        {
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

                document.Lines = document.Lines.Take(startIndex).Concat(newLines).Concat(document.Lines.Skip(endIndex + 1)).ToList();
                offset = newLines.Length - updatingLines.Length;
                skipRanges.Add(new Range(startIndex, endIndex));

                Console.WriteLine($"Updated block from {startIndex} to {endIndex}");
                Console.WriteLine("Previous content:");
                Console.WriteLine(string.Join(Environment.NewLine, updatingLines));
                Console.WriteLine("New content:");
                Console.WriteLine(string.Join(Environment.NewLine, newLines));
            }

            return offset;
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
                if (skipRanges.Any(range => (range.Start.Value + offset) <= i && (range.End.Value + offset) >= i))
                {
                    continue;
                }

                var openingMatch = StartingPattern.Matches(lines[i]);
                if (openingMatch.Count > 0)
                {
                    if (openLevel == 0)
                    {
                        startIndex = i;
                    }

                    openLevel += openingMatch.Count;
                }

                var closingMatch = EndingPattern.Matches(lines[i]);
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
        public Func<Match, string> Updater { get; } = updater;
        public Regex Pattern { get; } = pattern;

        override public int Apply(TextDocument document)
        {
            var offset = 0;

            for (int i = 0; i < document.Lines.Count; i++)
            {
                var matches = Pattern.Matches(document.Lines[i]);
                if (matches.Count == 0)
                {
                    continue;
                }

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
                        offset--;
                    }
                    else
                    {

                        span.SetContent(document, [newContent]);
                        if (isMultiLine)
                        {
                            offset += newContent.Split(Environment.NewLine).Length - 1;
                        }
                    }
                }
            }

            return offset;
        }
    }
}
