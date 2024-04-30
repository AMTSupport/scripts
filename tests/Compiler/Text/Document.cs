using Text;

[TestFixture]
public class DocumentTests
{
    private TextDocument _document;

    [SetUp]
    public void SetUp()
    {
        _document = new TextDocument([]);
    }
}
