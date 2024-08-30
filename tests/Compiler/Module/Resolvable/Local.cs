// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;

namespace Compiler.Test.Module.Resolvable;

[TestFixture]
public class LocalModuleTests {
    // [TestCaseSource(typeof(TestData), nameof(TestData.FixLinesCases))]
    // public string TestCompileDocument(string testContent)
    // {
    //     var module = new ResolvableLocalModule(TestUtils.GetModuleSpecFromContent(testContent));
    //     var compiledDocument = CompiledDocument.FromBuilder(module.Editor);
    //     return compiledDocument.GetContent();
    // }

    public class TestData {
        private static readonly string MULTILINE_STRING_LINES = """
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
        """;

        public static IEnumerable FixLinesCases {
            get {
                yield return new TestCaseData(
                    MULTILINE_STRING_LINES
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
