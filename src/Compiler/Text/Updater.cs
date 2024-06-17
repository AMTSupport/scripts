using System.Diagnostics.CodeAnalysis;
using System.Diagnostics.Contracts;
using System.Text;
using System.Text.RegularExpressions;
using CommandLine;
using NLog;

// TODO :: Ast based updater
namespace Compiler.Text;

public record SpanUpdateInfo(
    TextSpan TextSpan,
    int Offset
)
{
    public override string ToString() => $"{nameof(PatternUpdater)}({TextSpan} +- {Offset})";
}

public abstract class TextSpanUpdater
{
    /// <summary>
    /// Apply the update to the lines.
    /// </summary>
    /// <param name="lines">
    /// The document to apply the update to.
    /// </param>
    /// <returns>
    /// The number of lines changed by the update.
    /// </returns>
    public abstract SpanUpdateInfo[] Apply(ref List<string> lines);

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

    [Pure, ExcludeFromCodeCoverage(Justification = "Does nothing in this context.")]
    public override void PushByUpdate(SpanUpdateInfo updateInfo)
    {
        // Do Nothing
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
                Logger.Debug($"Skipping line {i} due to skip range.");
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

public class RegexUpdater(
    Regex pattern,
    UpdateOptions options,
    Func<Match, string?> updater
) : TextSpanUpdater
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public readonly Func<Match, string?> Updater = updater;
    public Regex Pattern
    {
        get
        {
            if (options.HasFlag(UpdateOptions.MatchEntireDocument))
            {
                return new Regex(pattern.ToString(), pattern.Options | RegexOptions.Multiline | RegexOptions.Singleline);
            }
            else
            {
                return new Regex(pattern.ToString(), pattern.Options | RegexOptions.Multiline);
            }
        }
    }

    // TODO - Refactor
    /// <summary>
    /// Applies the specified pattern to the given text document and returns an array of <see cref="SpanUpdateInfo"/> objects.
    /// </summary>
    /// <param name="document">The text document to apply the pattern to.</param>
    /// <returns>An array of <see cref="SpanUpdateInfo"/> objects representing the updates made to the document.</returns>
    override public SpanUpdateInfo[] Apply(ref List<string> lines)
    {
        var spanUpdateInfo = new List<SpanUpdateInfo>();
        var offset = 0;

        var multilinedContent = string.Join('\n', lines);
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
            startingColumn = match.Index - (contentBeforeThisLine + 1);
            if (isMultiLine)
            {
                endingColumn = multilineEndingIndex - (multilinedContent[..multilineEndingIndex].LastIndexOf('\n') + 1);
            }
            else
            {
                endingColumn = startingColumn + match.Length;
            }

            var span = new TextSpan(
                startingLineIndex,
                startingColumn,
                endingLineIndex,
                endingColumn
            );

            var newContent = Updater(match);

            // Remove the entire line if the replacement is empty and the match is the entire line.
            if (newContent == null && startingColumn == 0 && match.Length == lines[startingLineIndex].Length)
            {
                thisOffset += span.RemoveContent(ref lines);
            }
            else
            {
                var newLines = newContent == null ? [] : isMultiLine ? newContent.Split('\n') : [newContent];
                thisOffset += span.SetContent(ref lines, options, newLines);
                if (isMultiLine)
                {
                    thisOffset += newLines.Length - 1;
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
        // Do Nothing
    }

    public override string ToString() => $"{nameof(RegexUpdater)}({Pattern})";
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

    override public SpanUpdateInfo[] Apply(ref List<string> lines)
    {
        if (Span.StartingIndex < 0 || Span.EndingIndex >= lines.Count)
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

        switch (lines)
        {
            case null:
                Logger.Error("Document must not be null.");
                return [];
            case var l when l.Count == 0:
                Logger.Error("Document lines must not be null.");
                return [];
            case var l when l.Count <= Span.StartingIndex:
                Logger.Error($"Starting index must be less than the number of lines, got index {Span.StartingIndex} for length {l.Count}.");
                return [];
            case var l when l.Count <= Span.EndingIndex:
                Logger.Error($"Ending index must be less than the number of lines, got index {Span.EndingIndex} for length {l.Count}.");
                return [];
        }

        var startingLine = lines[Span.StartingIndex];
        var endingLine = lines[Span.EndingIndex];
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
            var updatingLine = lines[Span.StartingIndex][Span.StartingColumn..Span.EndingColumn];
            newLines = Updater([updatingLine]);
            offset = Span.SetContent(ref lines, options, newLines);
        }
        else
        {
            var updatingLines = lines.Skip(Span.StartingIndex).Take(Span.EndingIndex - Span.StartingIndex + 1).ToArray();
            // Trim the starting and ending lines to the correct columns.
            updatingLines[0] = lines[Span.StartingIndex][Span.StartingColumn..];
            updatingLines[^1] = lines[Span.EndingIndex][..Span.EndingColumn];

            newLines = Updater(updatingLines);
            offset = Span.SetContent(ref lines, options, newLines);
        }

        return [new SpanUpdateInfo(Span, offset)];
    }

    override public void PushByUpdate(SpanUpdateInfo updateInfo)
    {
        Logger.Debug($"Pushing with {updateInfo}.");

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

    public override string ToString() => $"{nameof(ExactUpdater)}({startingIndex}[{startingColumn}..]..{endingIndex}[..{endingColumn}])";
}
