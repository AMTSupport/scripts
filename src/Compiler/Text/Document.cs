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

        public void AddPatternEdit(
            [StringSyntax("Regex")] string openingPattern,
            [StringSyntax("Regex")] string closingPattern,
            Func<string[], string[]> updater)
        {
            VerifyNotAppliedOrError();

            TextUpdaters.Add(new PatternUpdater(
                new Regex(openingPattern),
                new Regex(closingPattern),
                updater
            ));
        }

        public void AddRegexEdit(
            [StringSyntax("Regex")] string pattern,
            Func<Match, string> updater)
        {
            VerifyNotAppliedOrError();

            Logger.Debug($"Adding regex updater for pattern: {pattern}");
            TextUpdaters.Add(new RegexUpdater(
                new Regex(pattern),
                updater
            ));
        }

        public void AddExactEdit(
            int startingIndex,
            int startingColumn,
            int endingIndex,
            int endingColumn,
            Func<string[], string[]> updater)
        {
            VerifyNotAppliedOrError();

            Logger.Debug($"Adding exact updater for range: {startingIndex}, {startingColumn}, {endingIndex}, {endingColumn}");
            TextUpdaters.Add(new ExactUpdater(
                startingIndex,
                startingColumn,
                endingIndex,
                endingColumn,
                updater
            ));
        }

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

        public string GetContent()
        {
            if (!EditApplied)
            {
                throw new Exception("Cannot get content from a document that has not had its edits applied.");
            }

            return string.Join(Environment.NewLine, Document.Lines);
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
