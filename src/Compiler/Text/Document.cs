// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Text.RegularExpressions;
using Compiler.Text.Updater;
using NLog;

namespace Compiler.Text;

public partial class TextDocument(string[] lines) {
    public readonly List<string> Lines = new(lines);
}

public class CompiledDocument(string[] lines) : TextDocument(lines) {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public string GetContent() => string.Join('\n', this.Lines);

    public static CompiledDocument FromBuilder(TextEditor builder, int indentBy = 0) {
        Logger.Trace($"Creating CompiledDocument from {builder}");

        builder.AddEdit(() => new IndentUpdater(indentBy));

        var lines = builder.Document.Lines;
        var spanUpdates = new List<SpanUpdateInfo>();
        var sortedUpdaters = builder.TextUpdaters.OrderBy(updater => updater.Priority).ToList();
        foreach (var textUpdater in sortedUpdaters) {
            // Logger.Debug($"Applying updater {textUpdater} with priority {textUpdater.Priority}");
            spanUpdates.ForEach(textUpdater.PushByUpdate);
            textUpdater.Apply(ref lines).ToList().ForEach(spanUpdates.Add);
        }

        return new CompiledDocument([.. lines]);
    }
}

public class TextEditor(TextDocument document) {
    public readonly TextDocument OriginalCopy = document;
    public readonly TextDocument Document = document;
    public readonly List<TextSpanUpdater> TextUpdaters = [];

    public void AddEdit(Func<TextSpanUpdater> updater) => this.TextUpdaters.Add(updater());

    public void AddPatternEdit(
        Regex openingPattern,
        Regex closingPattern,
        Func<string[], string[]> updater
    ) => this.AddPatternEdit(50, openingPattern, closingPattern, updater);

    public void AddPatternEdit(
        uint priority,
        Regex openingPattern,
        Regex closingPattern,
        Func<string[], string[]> updater
    ) => this.AddPatternEdit(priority, openingPattern, closingPattern, UpdateOptions.None, updater);

    public void AddPatternEdit(
        Regex openingPattern,
        Regex closingPattern,
        UpdateOptions options,
        Func<string[], string[]> updater
    ) => this.AddPatternEdit(50, openingPattern, closingPattern, options, updater);

    public void AddPatternEdit(
        uint priority,
        Regex openingPattern,
        Regex closingPattern,
        UpdateOptions options,
        Func<string[], string[]> updater
    ) => this.AddEdit(() => new PatternUpdater(
        priority,
        openingPattern,
        closingPattern,
        options,
        updater
    ));

    public void AddRegexEdit(
        Regex pattern,
        Func<Match, string?> updater
    ) => this.AddRegexEdit(50, pattern, updater);

    public void AddRegexEdit(
        Regex pattern,
        UpdateOptions options,
        Func<Match, string?> updater
    ) => this.AddRegexEdit(50, pattern, options, updater);

    public void AddRegexEdit(
        uint priority,
        Regex pattern,
        Func<Match, string?> updater
    ) => this.AddRegexEdit(priority, pattern, UpdateOptions.None, updater);

    public void AddRegexEdit(
        uint priority,
        Regex pattern,
        UpdateOptions options,
        Func<Match, string?> updater
    ) => this.AddEdit(() => new RegexUpdater(
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
    ) => this.AddExactEdit(50, startingIndex, startingColumn, endingIndex, endingColumn, updater);

    public void AddExactEdit(
        uint priority,
        int startingIndex,
        int startingColumn,
        int endingIndex,
        int endingColumn,
        Func<string[], string[]> updater
    ) => this.AddExactEdit(
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
    ) => this.AddEdit(() => new ExactUpdater(
        priority,
        startingIndex,
        startingColumn,
        endingIndex,
        endingColumn,
        options,
        updater
    ));
}
