namespace Text.Tests

{
    [TestFixture]
    public class PatternTests
    {
        private string[] lines;
        private TextEditor Editor;

        [SetUp]
        public void SetUp()
        {
            lines = [
                "@\"",
                "Doing cool stuff with this multiline string!",
                "",
                "This is the end of the string!",
                "\"@"
            ];

            Editor = new TextEditor(new(lines));
        }

        [Test]
        public void AddPatternEdit_ReplaceAllContent()
        {
            Editor.AddPatternEdit(openingPattern: "@\"", "\"@", _ => ["Updated content!"]);
            Editor.ApplyEdits();

            Assert.That(Editor.GetContent(), Is.EqualTo("Updated content!"));
        }

        [Test]
        public void AddPatternEdit_UseContentToUpdate()
        {
            Editor.AddPatternEdit("@\"", "\"@", content =>
            {
                return content.Select(line => line + "Updated content!").ToArray();
            });
            Editor.ApplyEdits();

            Assert.That(Editor.GetContent(), Is.EqualTo($"@\"Updated content!{Environment.NewLine}Doing cool stuff with this multiline string!Updated content!{Environment.NewLine}Updated content!{Environment.NewLine}This is the end of the string!Updated content!{Environment.NewLine}\"@Updated content!"));
        }

        [Test]
        public void AddPatternEdit_ReplaceContentWithEmpty()
        {
            Editor.AddPatternEdit("@\"", "\"@", _ => ["@\"", "\"@"]);
            Editor.ApplyEdits();

            Assert.That(Editor.GetContent(), Is.EqualTo($"@\"{Environment.NewLine}\"@"));
        }
    }

    [TestFixture]
    public class RegexTests
    {
        private string[] lines;
        private TextEditor Editor;

        [SetUp]
        public void SetUp()
        {
            lines = [
                "Hello,",
                "World!",
                "I'm the",
                "Document!"
            ];

            Editor = new TextEditor(new(lines));
        }

        [Test]
        public void AddRegexEdit_ReplaceEachLine()
        {
            Editor.AddRegexEdit("^.*$", _ => "Updated content!");
            Editor.ApplyEdits();

            Assert.That(Editor.GetContent(), Is.EqualTo($"Updated content!{Environment.NewLine}Updated content!{Environment.NewLine}Updated content!{Environment.NewLine}Updated content!"));
        }

        [Test]
        public void AddRegexEdit_ReplaceAllContent()
        {
            Editor.AddRegexEdit(".*", _ => "Updated content!");
            Editor.ApplyEdits();

            Assert.That(Editor.GetContent(), Is.EqualTo("Updated content!"));
        }

        [Test]
        public void AddRegexEdit_UseContentToUpdate()
        {
            Editor.AddRegexEdit(".*", match =>
            {
                return match.Value + " Updated content!";
            });
            Editor.ApplyEdits();

            Assert.That(Editor.GetContent(), Is.EqualTo("Hello, Updated content!World! Updated content!I'm the Updated content!Document! Updated content!"));
        }

        [Test]
        public void AddRegexEdit_ReplaceContentWithEmpty()
        {
            Editor.AddRegexEdit(".*", _ => "");
            Editor.ApplyEdits();

            Assert.That(Editor.GetContent(), Is.EqualTo(""));
        }
    }
}
