using System.Text;
using System.Text.RegularExpressions;
using NLog;

namespace Compiler.Text;

public partial class TextDocument(string[] lines)
{
    public readonly List<string> Lines = new(lines);
}

public class CompiledDocument(string[] lines) : TextDocument(lines)
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private string Text
    {
        get
        {
            return string.Join('\n', Lines);
        }
    }

    public string GetContent() => Text;

    public static implicit operator string(CompiledDocument document) => document.GetContent();

    public static CompiledDocument FromBuilder(TextEditor builder, int indentBy = 0)
    {
        Logger.Trace($"Creating CompiledDocument from {builder}");

        var indentString = new string(' ', indentBy);
        var lines = new List<string>(builder.Document.Lines.Select(line => $"{indentString}{line}"));
        var spanUpdates = new List<SpanUpdateInfo>();
        foreach (var textUpdater in builder.TextUpdaters)
        {
            Logger.Debug($"Applying updater {textUpdater}");
            spanUpdates.ForEach(textUpdater.PushByUpdate);
            textUpdater.Apply(ref lines).ToList().ForEach(spanUpdates.Add);
        }

        return new CompiledDocument([.. lines]);
    }
}

public class TextEditor(TextDocument document)
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public TextDocument Document { get; } = document;
    public List<TextSpanUpdater> TextUpdaters { get; } = [];

    public void AddEdit(Func<TextSpanUpdater> updater)
    {
        Logger.Debug($"Adding {updater.GetType().Name} with spec {updater}");
        TextUpdaters.Add(updater());
    }

    public void AddPatternEdit(
        Regex openingPattern,
        Regex closingPattern,
        Func<string[], string[]> updater
    ) => AddPatternEdit(openingPattern, closingPattern, UpdateOptions.None, updater);

    public void AddPatternEdit(
        Regex openingPattern,
        Regex closingPattern,
        UpdateOptions options,
        Func<string[], string[]> updater
    ) => AddEdit(() => new PatternUpdater(
        openingPattern,
        closingPattern,
        options,
        updater
    ));

    public void AddRegexEdit(
        Regex pattern,
        Func<Match, string?> updater
    ) => AddRegexEdit(pattern, UpdateOptions.None, updater);

    public void AddRegexEdit(
        Regex pattern,
        UpdateOptions options,
        Func<Match, string?> updater
    ) => AddEdit(() => new RegexUpdater(
        pattern,
        options,
        updater
    ));

    public void AddExactEdit(
        int startingIndex,
        int startingColumn,
        int endingIndex,
        int endingColumn,
        Func<string[], string[]> updater
    ) => AddExactEdit(
        startingIndex,
        startingColumn,
        endingIndex,
        endingColumn,
        UpdateOptions.None,
        updater
    );

    public void AddExactEdit(
        int startingIndex,
        int startingColumn,
        int endingIndex,
        int endingColumn,
        UpdateOptions options,
        Func<string[], string[]> updater
    ) => AddEdit(() => new ExactUpdater(
        startingIndex,
        startingColumn,
        endingIndex,
        endingColumn,
        options,
        updater
    ));

    public override string ToString()
    {
        var sb = new StringBuilder()
            .AppendLine("TextEditor:")
            .AppendLine("  Document:")
            .AppendLine('\t' + string.Join("\n\t", Document.Lines))
            .AppendLine("  TextUpdaters:")
            .AppendLine('\t' + string.Join("\n\t", TextUpdaters.Select(updater => updater.ToString())));
        return sb.ToString();
    }
}
