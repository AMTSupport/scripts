namespace Text.Tests

{
    [TestFixture]
    public class PatternTests
    {
        private string[] lines;
        private TextDocument document;

        [SetUp]
        public void SetUp()
        {
            lines = [
                "\"@",
                "Doing cool stuff with this multiline string!",
                "",
                "This is the end of the string!",
                "@\""
            ];

            document = new TextDocument(lines);
        }
    }
}
