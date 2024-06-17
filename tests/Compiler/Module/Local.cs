using Compiler.Module;
using Compiler.Requirements;
using Compiler.Text;
using System.Collections;

namespace Compiler.Test.Module;

[TestFixture]
public class LocalModuleTests
{

    [TestCaseSource(typeof(TestData), nameof(TestData.FixLinesCases))]
    public string FixLines(
        string[] testLines
    )
    {
        var module = new LocalFileModule("test.ps1", new ModuleSpec("test"), new TextDocument(testLines), true, true);
        module.FixLines();

        var compiledDocument = CompiledDocument.FromBuilder(module.Document);
        return compiledDocument.GetContent();
    }

    public class TestData
    {
        private static readonly string[] MULTILINE_STRING_LINES = """
                @"
            Doing cool stuff with this indented multiline string!

            This is the end of the string!
            "@;
        @'
        This is a multiline string with single quotes!
        '@;
                            $MyVariable = @"
                This is a multiline string with a variable inside: $MyVariable
                "@;
        """.Split('\n');

        public static IEnumerable FixLinesCases
        {
            get
            {
                yield return new TestCaseData(
                    arg: MULTILINE_STRING_LINES
                ).Returns("""
                        @"
                Doing cool stuff with this indented multiline string!

                This is the end of the string!
                "@;
                @'
                This is a multiline string with single quotes!
                '@;
                                    $MyVariable = @"
                This is a multiline string with a variable inside: $MyVariable
                "@;
                """).SetName("Fix multiline string indents");
            }
        }
    }
}
