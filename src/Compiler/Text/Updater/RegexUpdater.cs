using System.Text.RegularExpressions;
using NLog;

namespace Compiler.Text.Updater;

public class RegexUpdater(
    uint priority,
    Regex pattern,
    UpdateOptions options,
    Func<Match, string?> updater
) : TextSpanUpdater(priority)
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

    public override string ToString() => $"{nameof(RegexUpdater)}({Pattern})";
}
