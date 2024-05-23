using System.Diagnostics.CodeAnalysis;
using System.Text.RegularExpressions;
using NLog;
using Text.Updater;

namespace Text
{
    public class TextDocument(string[] lines)
    {
        public List<string> Lines { get; set; } = new List<string>(lines);
    }

    public class TextEditor(TextDocument document)
    {
        private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

        public TextDocument Document { get; set; } = document;
        public List<TextSpanUpdater> TextUpdaters { get; set; } = [];
        public bool EditApplied { get; set; } = false;

        public void AddEdit(Func<TextSpanUpdater> updater)
        {
            VerifyNotAppliedOrError();
            Logger.Debug($"Adding {updater.GetType().Name} with spec {updater}");
            TextUpdaters.Add(updater());
        }

        public void AddPatternEdit(
            [StringSyntax("Regex")] string openingPattern,
            [StringSyntax("Regex")] string closingPattern,
            Func<string[], string[]> updater
        ) => AddPatternEdit(openingPattern, closingPattern, UpdateOptions.None, updater);

        public void AddPatternEdit(
            [StringSyntax("Regex")] string openingPattern,
            [StringSyntax("Regex")] string closingPattern,
            UpdateOptions options,
            Func<string[], string[]> updater
        ) => AddEdit(() => new PatternUpdater(
            new Regex(openingPattern),
            new Regex(closingPattern),
            options,
            updater
        ));

        public void AddRegexEdit(
            [StringSyntax("Regex")] string pattern,
            Func<Match, string> updater
        ) => AddRegexEdit(pattern, UpdateOptions.None, updater);

        public void AddRegexEdit(
            [StringSyntax("Regex")] string pattern,
            UpdateOptions options,
            Func<Match, string> updater
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

        public void ApplyEdits()
        {
            VerifyNotAppliedOrError();

            Logger.Trace("Applying edits to document");
            var spanUpdates = new List<SpanUpdateInfo>();
            foreach (var textUpdater in TextUpdaters)
            {
                Logger.Debug($"Applying updater: {textUpdater.GetType().Name} to");
                spanUpdates.ForEach(textUpdater.PushByUpdate);
                textUpdater.Apply(Document).ToList().ForEach(spanUpdates.Add);
            }

            EditApplied = true;
        }

        public string GetContent(int indent = 0)
        {
            if (!EditApplied)
            {
                throw new Exception("Cannot get content from a document that has not had its edits applied.");
            }

            var indentString = new string(' ', indent);
            var lines = Document.Lines.Select(line => $"{indentString}{line}");
            return string.Join('\n', lines);
        }

        private void VerifyNotAppliedOrError()
        {
            if (EditApplied)
            {
                throw new Exception("Cannot add a range edit to a document that has had its edits applied.");
            }
        }
    }
}
