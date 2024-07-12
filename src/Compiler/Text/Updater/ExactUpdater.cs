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
) : TextSpanUpdater(priority)
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public Func<string[], string[]> Updater = updater;
    public TextSpan Span { get; } = new TextSpan(startingIndex, startingColumn, endingIndex, endingColumn);

    override public SpanUpdateInfo[] Apply([NotNull] ref List<string> lines)
    {
        ArgumentNullException.ThrowIfNull(lines);

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
        if (Span.StartingIndex >= updateInfo.TextSpan.StartingIndex)
        {
            Span.StartingIndex += updateInfo.Offset;
        }

        if (Span.EndingIndex >= updateInfo.TextSpan.StartingIndex)
        {
            Span.EndingIndex += updateInfo.Offset;
        }
    }

    public override string ToString() => $"{nameof(ExactUpdater)}({startingIndex}[{startingColumn}..]..{endingIndex}[..{endingColumn}])";
}
