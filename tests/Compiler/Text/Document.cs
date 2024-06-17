using Compiler.Text;

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

    public static partial class TestData;
}
