using System.Text;
using System.Text.RegularExpressions;
using CommandLine;
using NLog;

namespace Compiler.Text.Updater;

public class PatternUpdater(
    uint priority,
    Regex startingPattern,
    Regex endingPattern,
    UpdateOptions options,
    Func<string[], string[]> updater
) : TextSpanUpdater(priority)
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public Func<string[], string[]> Updater { get; } = updater;
    public Regex StartingPattern { get; } = startingPattern;
    public Regex EndingPattern { get; } = endingPattern;

    override public SpanUpdateInfo[] Apply(ref List<string> lines)
    {
        var spanUpdateInfo = new List<SpanUpdateInfo>();
        var skipRanges = new HashSet<Range>();
        var offset = 0;

        while (true)
        {
            var (startIndex, endIndex) = FindStartToEndBlock([.. lines], offset, skipRanges);
            if (startIndex == -1 || endIndex == -1)
            {
                break;
            }

            var span = new TextSpan(
                startIndex,
                0,
                endIndex,
                lines[endIndex].Length
            );

            var updatingLines = lines[startIndex..(endIndex + 1)].ToArray();
            var newLines = Updater(updatingLines);
            var thisOffset = span.SetContent(ref lines, options, newLines);

            offset += thisOffset;
            skipRanges.Add(new Range(startIndex, endIndex));
            spanUpdateInfo.Add(new SpanUpdateInfo(span, thisOffset));
        }

        return [.. spanUpdateInfo];
    }

    private (int, int) FindStartToEndBlock(
        string[] lines,
        int offset,
        HashSet<Range> skipRanges
    )
    {
        if (lines == null || lines.Length == 0)
        {
            return (-1, -1);
        }

        var offsetSkipRanges = new HashSet<IEnumerable<int>>();
        foreach (var range in skipRanges)
        {
            var clampedStart = Math.Clamp(range.Start.Value + offset, 0, lines.Length - 1);
            var clampedEnd = Math.Clamp(range.End.Value + offset, 0, lines.Length - 1);
            if (clampedStart < clampedEnd)
            {
                offsetSkipRanges.Add(Enumerable.Range(clampedStart, clampedEnd - clampedStart + 1));
            }
        }

        int startIndex = -1;
        int endIndex = -1;
        int openLevel = 0;

        for (int i = 0; i < lines.Length; i++)
        {
            var clonedLine = lines[i].Clone().Cast<string>()!;
            if (offsetSkipRanges.Any(range => range.Contains(i)))
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
                var lineOffset = 0;
                foreach (Match match in openingMatch)
                {
                    clonedLine = new StringBuilder()
                        .Append(clonedLine[..(match.Index + lineOffset)])
                        .Append(clonedLine[(match.Index + lineOffset + match.Length)..])
                        .ToString();
                    lineOffset -= match.Length;
                }
            }

            if (openLevel > 0)
            {
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
        }

        return (startIndex, endIndex);
    }

    public override string ToString() => $"{nameof(PatternUpdater)}({StartingPattern} -> {EndingPattern})";
}