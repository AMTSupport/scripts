using System.Collections;
using System.Text.RegularExpressions;
using Text;
using Text.Updater;

namespace Compiler.Test.Text;

[TestFixture]
public partial class DocumentTests
{
    private TextEditor Editor;

    [SetUp]
    public void SetUp()
    {
        Editor = new TextEditor(new TextDocument([]));
    }

    [Test]
    public void ApplyEdits_ThrowsException_WhenAlreadyApplied()
    {
        Editor.ApplyEdits();
        Assert.Throws<Exception>(() => Editor.ApplyEdits());
    }

    [Test]
    public void GetContent_ThrowsException_WhenEditsNotApplied()
    {
        Assert.Throws<Exception>(() => Editor.GetContent());
    }

    [Test]
    public void AddEdits_ThrowsException_WhenAlreadyApplied()
    {
        Editor.ApplyEdits();
        Assert.Throws<Exception>(() => Editor.AddExactEdit(0, 0, 0, 0, _ => _));
    }

    public static partial class TestData
    {
        public static IEnumerable CaseForEachUpdaterType
        {
            get
            {
                yield return new TestCaseData(new PatternUpdater(TestRegex(), TestRegex(), UpdateOptions.None, _ => [])).SetCategory("PatternUpdater");
                yield return new TestCaseData(new RegexUpdater(".*", UpdateOptions.None, _ => "")).SetCategory("RegexUpdater");
                yield return new TestCaseData(new ExactUpdater(0, 0, 0, 0, UpdateOptions.None, _ => [])).SetCategory("ExactUpdater");
            }
        }

        [GeneratedRegex(".*")]
        private static partial Regex TestRegex();
    }
}
