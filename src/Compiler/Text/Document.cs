using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Compiler.Text.Updater;
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
    public string ContentHash
    {
        get
        {
            var hash = SHA256.HashData(Encoding.UTF8.GetBytes(Text));
            return Convert.ToHexString(hash);
        }
    }

    public string GetContent() => Text;

    public static implicit operator string(CompiledDocument document) => document.GetContent();

    public static CompiledDocument FromBuilder(TextEditor builder, int indentBy = 0)
    {
        Logger.Trace($"Creating CompiledDocument from {builder}");

        builder.AddEdit(() => new IndentUpdater(indentBy));

        var lines = builder.Document.Lines;
        var spanUpdates = new List<SpanUpdateInfo>();
        var sortedUpdaters = builder.TextUpdaters.OrderBy(updater => updater.Priority).ToList();
        foreach (var textUpdater in sortedUpdaters)
        {
            Logger.Debug($"Applying updater {textUpdater} with priority {textUpdater.Priority}");
            spanUpdates.ForEach(textUpdater.PushByUpdate);
            textUpdater.Apply(ref lines).ToList().ForEach(spanUpdates.Add);
        }

        return new CompiledDocument([.. lines]);
    }
}

public class TextEditor(TextDocument document)
{
    public TextDocument Document { get; } = document;
    public List<TextSpanUpdater> TextUpdaters { get; } = [];

    public void AddEdit(Func<TextSpanUpdater> updater)
    {
        TextUpdaters.Add(updater());
    }

    public void AddPatternEdit(
        Regex openingPattern,
        Regex closingPattern,
        Func<string[], string[]> updater
    ) => AddPatternEdit(50, openingPattern, closingPattern, updater);

    public void AddPatternEdit(
        uint priority,
        Regex openingPattern,
        Regex closingPattern,
        Func<string[], string[]> updater
    ) => AddPatternEdit(priority, openingPattern, closingPattern, UpdateOptions.None, updater);

    public void AddPatternEdit(
        Regex openingPattern,
        Regex closingPattern,
        UpdateOptions options,
        Func<string[], string[]> updater
    ) => AddPatternEdit(50, openingPattern, closingPattern, options, updater);

    public void AddPatternEdit(
        uint priority,
        Regex openingPattern,
        Regex closingPattern,
        UpdateOptions options,
        Func<string[], string[]> updater
    ) => AddEdit(() => new PatternUpdater(
        priority,
        openingPattern,
        closingPattern,
        options,
        updater
    ));

    public void AddRegexEdit(
        Regex pattern,
        Func<Match, string?> updater
    ) => AddRegexEdit(50, pattern, updater);

    public void AddRegexEdit(
        Regex pattern,
        UpdateOptions options,
        Func<Match, string?> updater
    ) => AddRegexEdit(50, pattern, options, updater);

    public void AddRegexEdit(
        uint priority,
        Regex pattern,
        Func<Match, string?> updater
    ) => AddRegexEdit(priority, pattern, UpdateOptions.None, updater);

    public void AddRegexEdit(
        uint priority,
        Regex pattern,
        UpdateOptions options,
        Func<Match, string?> updater
    ) => AddEdit(() => new RegexUpdater(
        priority,
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
    ) => AddExactEdit(50, startingIndex, startingColumn, endingIndex, endingColumn, updater);

    public void AddExactEdit(
        uint priority,
        int startingIndex,
        int startingColumn,
        int endingIndex,
        int endingColumn,
        Func<string[], string[]> updater
    ) => AddExactEdit(
        priority,
        startingIndex,
        startingColumn,
        endingIndex,
        endingColumn,
        UpdateOptions.None,
        updater
    );

    public void AddExactEdit(
        uint priority,
        int startingIndex,
        int startingColumn,
        int endingIndex,
        int endingColumn,
        UpdateOptions options,
        Func<string[], string[]> updater
    ) => AddEdit(() => new ExactUpdater(
        priority,
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
            // .AppendLine('\t' + string.Join("\n\t", Document.Lines))
            .AppendLine("  TextUpdaters:")
            .AppendLine('\t' + string.Join("\n\t", TextUpdaters.Select(updater => updater.ToString())));
        return sb.ToString();
    }
}
