// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using System.Management.Automation.Language;
using System.Text.RegularExpressions;
using Compiler.Text.Updater;
using LanguageExt;

namespace Compiler.Text;

public class TextDocument : IDisposable {
    private readonly List<string> Lines;
    private StreamReader? FileStream;
    protected Fin<ScriptBlockAst>? RequirementsAst;

    public TextDocument(string[] lines) => this.Lines = [.. lines];

    public TextDocument(string path) {
        this.Lines = [];
        this.FileStream = new StreamReader(path);
    }

    public Fin<ScriptBlockAst> GetRequirementsAst() {
        if (this.RequirementsAst is not null) return this.RequirementsAst;

        this.GetLines(line => {
            line = line.Trim();
            return string.IsNullOrWhiteSpace(line) ||
                line.StartsWith("#requires", StringComparison.OrdinalIgnoreCase) ||
                line.StartsWith("using", StringComparison.OrdinalIgnoreCase);
        });

        return this.RequirementsAst = AstHelper.GetAstReportingErrors(
            string.Join('\n', this.Lines),
            None,
            ["ModuleNotFoundDuringParse"]
        );
    }

    [return: NotNull]
    public IEnumerable<string> GetLines(Predicate<string>? readerStopCondition = null) {
        if (this.FileStream is not null) {
            while (!this.FileStream.EndOfStream && this.FileStream.ReadLine() is string line) {
                this.Lines.Add((string)line.Clone()); // Clone the line incase it is modified in the predicate.
                if (readerStopCondition is not null && readerStopCondition(line)) {
                    break;
                }
            }

            if (this.FileStream.EndOfStream) {
                this.FileStream.Dispose();
                this.FileStream = null;
            }
        }

        return this.Lines;
    }

    public void Dispose() {
        this.FileStream?.Dispose();
        GC.SuppressFinalize(this);
    }
}

public sealed class CompiledDocument(
    string[] lines,
    ScriptBlockAst ast
) : TextDocument(lines) {
    public ScriptBlockAst Ast { get; private init; } = ast;

    public string GetContent() => string.Join('\n', this.GetLines());

    public static Fin<CompiledDocument> FromBuilder(TextEditor builder, int indentBy = 0) {
        builder.AddEdit(() => new IndentUpdater(indentBy));

        var lines = builder.Document.GetLines().ToList();
        var spanUpdates = new List<SpanUpdateInfo>();
        var sortedUpdaters = builder.TextUpdaters.OrderBy(updater => updater.Priority).ToList();
        foreach (var textUpdater in sortedUpdaters) {
            spanUpdates.ForEach(textUpdater.PushByUpdate);
            var updateResult = textUpdater.Apply(lines);

            updateResult.IfSucc(spanUpdates.AddRange);
            if (updateResult.IsErr(out var err, out _)) {
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
