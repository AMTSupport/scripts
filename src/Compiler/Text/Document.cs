using System.Diagnostics.CodeAnalysis;
using System.Text.RegularExpressions;
using Text.Updater;

namespace Text
{
    public class TextDocument(string[] lines)
    {
        public List<string> Lines { get; set; } = new List<string>(lines);
    }

    public class TextEditor(TextDocument document)
    {
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

            TextUpdaters.Add(new RegexUpdater(
                new Regex(pattern),
                updater
            ));
        }

        public void ApplyRangeEdits()
        {
            VerifyNotAppliedOrError();

            foreach (var textUpdater in TextUpdaters)
            {
                textUpdater.Apply(Document);
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
