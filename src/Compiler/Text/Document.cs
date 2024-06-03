using System.Diagnostics.CodeAnalysis;
using System.Text.RegularExpressions;
using NLog;
using Text.Updater;

namespace Text
{
    public partial class TextDocument(string[] lines)
    {
        public readonly List<string> Lines = new(lines);
    }

    public class CompiledDocument(string[] lines) : TextDocument(lines)
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

        public string GetContent(int indent = 0)
        {
            var indentString = new string(' ', indent);
            var lines = Lines.Select(line => $"{indentString}{line}");

            return string.Join('\n', lines);
        }

        public static implicit operator string(CompiledDocument document) => document.GetContent();

        public static CompiledDocument FromBuilder(TextEditor builder)
        {
            Logger.Trace($"Creating CompiledDocument from {builder}");

            var lines = new List<string>(builder.Document.Lines);
            var spanUpdates = new List<SpanUpdateInfo>();
            foreach (var textUpdater in builder.TextUpdaters)
            {
                Logger.Debug($"Applying updater: {textUpdater.GetType().Name} with spec {textUpdater} to document.");
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
    }
}
