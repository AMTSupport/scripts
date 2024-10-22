// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using System.Management.Automation.Language;
using System.Runtime.CompilerServices;
using System.Text.RegularExpressions;
using Compiler.Text.Updater;
using Compiler.Text.Updater.Built;
using LanguageExt;
using NLog;

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

        this.GetLines((line, _) => {
            line = line.Trim();
            return string.IsNullOrWhiteSpace(line) ||
                line.StartsWith("#requires", StringComparison.OrdinalIgnoreCase) ||
                line.StartsWith("using", StringComparison.OrdinalIgnoreCase);
        });

        return this.RequirementsAst = AstHelper.GetAstReportingErrors(
            string.Join('\n', this.Lines),
            None,
            ["ModuleNotFoundDuringParse"],
            out _
        );
    }

    [return: NotNull]
    public List<string> GetLines(Func<string, int, bool>? readerStopCondition = null) {
        if (this.FileStream is not null) {
            var lineIndex = this.Lines.Count;
            while (!this.FileStream.EndOfStream && this.FileStream.ReadLine() is string line) {
                lineIndex++;
                this.Lines.Add((string)line.Clone()); // Clone the line incase it is modified in the predicate.
                if (readerStopCondition is not null && readerStopCondition(line, lineIndex)) {
                    break;
                }
            }

            if (this.FileStream.EndOfStream) {
                this.FileStream.Dispose();
                this.FileStream = null;
            }
        }

        var copiedLines = new string[this.Lines.Count];
        this.Lines.CopyTo(copiedLines);
        return [.. copiedLines];
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
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    public ScriptBlockAst Ast { get; private init; } = ast;

    public string GetContent() => string.Join('\n', this.GetLines());

    public static Fin<CompiledDocument> FromBuilder(TextEditor builder, int indentBy = 0) {
        if (indentBy != 0) builder.AddEdit(() => new IndentUpdater(indentBy));

        var lines = builder.Document.GetLines().ToList();
        var spanUpdates = new List<SpanUpdateInfo>();
        var sortedUpdaters = builder.TextUpdaters.OrderBy(updater => updater.Updater.Priority).ToList();
        Logger.Debug($"Applying in order->{string.Join("\n\t", sortedUpdaters)}");
        foreach (var textUpdater in sortedUpdaters) {
            spanUpdates.ForEach(textUpdater.Updater.PushByUpdate);
            Fin<IEnumerable<SpanUpdateInfo>> updateResult;
            try {
                updateResult = textUpdater.Updater.Apply(lines);
            } catch (Exception e) {
                return Error.New(
                    $"Error applying update: {textUpdater}",
                    e
                );
            }

            if (updateResult.IsErr(out var err, out var updates)) {
                if (err is WrappedErrorWithDebuggableContent wrappedError) {
                    return err;
                }

                return new WrappedErrorWithDebuggableContent($"Error applying update: {textUpdater}", string.Join('\n', lines), err);
            }

            spanUpdates.AddRange(updates);
        }

        return AstHelper.GetAstReportingErrors(
        string.Join('\n', lines),
            None,
            ["ModuleNotFoundDuringParse"],
            out _
        ).AndThen(ast => new CompiledDocument([.. lines], ast));
    }
}

public class TextEditor(TextDocument document) {
    public record SourcedTextUpdater(
        TextSpanUpdater Updater,
        string SourceFile,
        string SourceMember,
        int SourceLine
    ) {
        private static readonly string RootDir = $"src{Path.DirectorySeparatorChar}Compiler";

        public override string ToString() {
            var sourceFile = this.SourceFile;
            var rootDirIndex = sourceFile.IndexOf(RootDir, StringComparison.Ordinal);
            if (rootDirIndex != -1) {
                sourceFile = sourceFile[rootDirIndex..];
            }

            return $"{sourceFile}::{this.SourceMember}::{this.SourceLine}->{this.Updater}";
        }
    }

    public readonly TextDocument OriginalCopy = document;
    public readonly TextDocument Document = document;
    public readonly List<SourcedTextUpdater> TextUpdaters = [];

    public void AddEdit(
        [NotNull] Func<TextSpanUpdater> updater,
        [CallerFilePath] string callerFile = "",
        [CallerMemberName] string callerMember = "",
        [CallerLineNumber] int callerLine = default
    ) => this.TextUpdaters.Add(new(updater(), callerFile, callerMember, callerLine));

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void AddPatternEdit(
        Regex openingPattern,
        Regex closingPattern,
        Func<string[], string[]> updater,
        [CallerFilePath] string callerFile = "",
        [CallerMemberName] string callerMember = "",
        [CallerLineNumber] int callerLine = default
    ) => this.AddPatternEdit(50, openingPattern, closingPattern, updater, callerFile, callerMember, callerLine);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void AddPatternEdit(
        uint priority,
        Regex openingPattern,
        Regex closingPattern,
        Func<string[], string[]> updater,
        [CallerFilePath] string callerFile = "",
        [CallerMemberName] string callerMember = "",
        [CallerLineNumber] int callerLine = default
    ) => this.AddPatternEdit(priority, openingPattern, closingPattern, UpdateOptions.None, updater, callerFile, callerMember, callerLine);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void AddPatternEdit(
        Regex openingPattern,
        Regex closingPattern,
        UpdateOptions options,
        Func<string[], string[]> updater,
        [CallerFilePath] string callerFile = "",
        [CallerMemberName] string callerMember = "",
        [CallerLineNumber] int callerLine = default
    ) => this.AddPatternEdit(50, openingPattern, closingPattern, options, updater, callerFile, callerMember, callerLine);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void AddPatternEdit(
        uint priority,
        Regex openingPattern,
        Regex closingPattern,
        UpdateOptions options,
        Func<string[], string[]> updater,
        [CallerFilePath] string callerFile = "",
        [CallerMemberName] string callerMember = "",
        [CallerLineNumber] int callerLine = default
    ) => this.AddEdit(() => new PatternUpdater(priority, openingPattern, closingPattern, options, updater), callerFile, callerMember, callerLine);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void AddRegexEdit(
        Regex pattern,
        Func<Match, string?> updater,
        [CallerFilePath] string callerFile = "",
        [CallerMemberName] string callerMember = "",
        [CallerLineNumber] int callerLine = default
    ) => this.AddRegexEdit(50, pattern, updater, callerFile, callerMember, callerLine);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void AddRegexEdit(
        Regex pattern,
        UpdateOptions options,
        Func<Match, string?> updater,
        [CallerFilePath] string callerFile = "",
        [CallerMemberName] string callerMember = "",
        [CallerLineNumber] int callerLine = default
    ) => this.AddRegexEdit(50, pattern, options, updater, callerFile, callerMember, callerLine);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void AddRegexEdit(
        uint priority,
        Regex pattern,
        Func<Match, string?> updater,
        [CallerFilePath] string callerFile = "",
        [CallerMemberName] string callerMember = "",
        [CallerLineNumber] int callerLine = default
    ) => this.AddRegexEdit(priority, pattern, UpdateOptions.None, updater, callerFile, callerMember, callerLine);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void AddRegexEdit(
        uint priority,
        Regex pattern,
        UpdateOptions options,
        Func<Match, string?> updater,
        [CallerFilePath] string callerFile = "",
        [CallerMemberName] string callerMember = "",
        [CallerLineNumber] int callerLine = default
    ) => this.AddEdit(() => new RegexUpdater(priority, pattern, options, updater), callerFile, callerMember, callerLine);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void AddExactEdit(
        int startingIndex,
        int startingColumn,
        int endingIndex,
        int endingColumn,
        Func<string[], string[]> updater,
        [CallerFilePath] string callerFile = "",
        [CallerMemberName] string callerMember = "",
        [CallerLineNumber] int callerLine = default
    ) => this.AddExactEdit(startingIndex, startingColumn, endingIndex, endingColumn, UpdateOptions.None, updater, callerFile, callerMember, callerLine);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void AddExactEdit(
        int startingIndex,
        int startingColumn,
        int endingIndex,
        int endingColumn,
        UpdateOptions options,
        Func<string[], string[]> updater,
        [CallerFilePath] string callerFile = "",
        [CallerMemberName] string callerMember = "",
        [CallerLineNumber] int callerLine = default
    ) => this.AddExactEdit(50, startingIndex, startingColumn, endingIndex, endingColumn, options, updater, callerFile, callerMember, callerLine);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void AddExactEdit(
        uint priority,
        int startingIndex,
        int startingColumn,
        int endingIndex,
        int endingColumn,
        Func<string[], string[]> updater,
        [CallerFilePath] string callerFile = "",
        [CallerMemberName] string callerMember = "",
        [CallerLineNumber] int callerLine = default
    ) => this.AddExactEdit(priority, startingIndex, startingColumn, endingIndex, endingColumn, UpdateOptions.None, updater, callerFile, callerMember, callerLine);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void AddExactEdit(
        uint priority,
        int startingIndex,
        int startingColumn,
        int endingIndex,
        int endingColumn,
        UpdateOptions options,
        Func<string[], string[]> updater,
        [CallerFilePath] string callerFile = "",
        [CallerMemberName] string callerMember = "",
        [CallerLineNumber] int callerLine = default
    ) => this.AddEdit(() => new ExactUpdater(priority, startingIndex, startingColumn, endingIndex, endingColumn, options, updater), callerFile, callerMember, callerLine);
}
