using System.Reflection;
using Text;

namespace Compiler.Test.Text;

[TestFixture]
public class DocumentTests
{
    private TextEditor Editor;

    [SetUp]
    public void SetUp()
    {
        Editor = new TextEditor(new TextDocument([]));
    }

    [Test]
    public void AddPaternEdit_ThrowsException_WhenAlreadyApplied()
    {
        Editor.ApplyEdits();
        Assert.Throws<Exception>(() => Editor.AddPatternEdit("", "", _ => _));
    }

    [Test]
    public void AddRegexEdit_ThrowsException_WhenAlreadyApplied()
    {
        Editor.ApplyEdits();
        Assert.Throws<Exception>(() => Editor.AddRegexEdit("", _ => ""));
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
    public void GetContent_ReturnsContent_WhenEditsApplied()
    {
        Editor.AddPatternEdit("", "", _ => ["Hello, World!"]);
        Editor.ApplyEdits();
        Assert.That(Editor.GetContent(), Is.EqualTo("Hello, World!"));
    }
}
