// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using System.Management.Automation.Language;
using System.Text.RegularExpressions;
using Compiler.Text.Updater;
using LanguageExt;
using NLog;

namespace Compiler.Text;

public partial class TextDocument([NotNull] string[] lines) {
    public readonly List<string> Lines = new(lines);
}

public sealed class CompiledDocument(
    string[] lines,
    ScriptBlockAst ast
) : TextDocument(lines) {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public ScriptBlockAst Ast { get; private init; } = ast;

    public string GetContent() => string.Join('\n', this.Lines);

    public static Fin<CompiledDocument> FromBuilder(TextEditor builder, int indentBy = 0) {
        builder.AddEdit(() => new IndentUpdater(indentBy));

        var lines = builder.Document.Lines;
        var spanUpdates = new List<SpanUpdateInfo>();
        var sortedUpdaters = builder.TextUpdaters.OrderBy(updater => updater.Priority).ToList();
        foreach (var textUpdater in sortedUpdaters) {
            spanUpdates.ForEach(textUpdater.PushByUpdate);
            var updateResult = textUpdater.Apply(lines);

            updateResult.IfSucc(spanUpdates.AddRange);
            if (updateResult.IsErr(out var err, out _)) {
                Logger.Error($"Error while applying updater {textUpdater}: {err}");
                return err;
            }
        }

        return AstHelper.GetAstReportingErrors(
            string.Join('\n', lines),
            None,
            ["ModuleNotFoundDuringParse"]
        ).AndThen(ast => new CompiledDocument([.. lines], ast));
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
    ) => this.AddEdit(() => new PatternUpdater(priority, openingPattern, closingPattern, options, updater));

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
    ) => this.AddEdit(() => new RegexUpdater(priority, pattern, options, updater));

    public void AddExactEdit(
        int startingIndex,
        int startingColumn,
        int endingIndex,
        int endingColumn,
        Func<string[], string[]> updater
    ) => this.AddExactEdit(startingIndex, startingColumn, endingIndex, endingColumn, UpdateOptions.None, updater);

    public void AddExactEdit(
        int startingIndex,
        int startingColumn,
        int endingIndex,
        int endingColumn,
        UpdateOptions options,
        Func<string[], string[]> updater
    ) => this.AddExactEdit(50, startingIndex, startingColumn, endingIndex, endingColumn, options, updater);

    public void AddExactEdit(
        uint priority,
        int startingIndex,
        int startingColumn,
        int endingIndex,
        int endingColumn,
        Func<string[], string[]> updater
    ) => this.AddExactEdit(priority, startingIndex, startingColumn, endingIndex, endingColumn, UpdateOptions.None, updater);

    public void AddExactEdit(
        uint priority,
        int startingIndex,
        int startingColumn,
        int endingIndex,
        int endingColumn,
        UpdateOptions options,
        Func<string[], string[]> updater
    ) => this.AddEdit(() => new ExactUpdater(priority, startingIndex, startingColumn, endingIndex, endingColumn, options, updater));
}
