// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Text.RegularExpressions;
using Compiler.Text;
using Compiler.Text.Updater;

namespace Compiler.Test.Module.Resolvable;

[TestFixture]
public partial class CompiledScriptTest {
    [TestCaseSource(typeof(TestData), nameof(TestData.TestCases))]
    public string Test(
        TextSpanUpdater updater,
        string content
    ) {
        var document = new TextEditor(new TextDocument(content.Split('\n')))!;
        document.AddEdit(() => updater);

        var compiled = CompiledDocument.FromBuilder(document).ThrowIfFail();
        return compiled.GetContent();
    }

    public static partial class TestData {
        [GeneratedRegex(@"^(?!\n)*$")]
        public static partial Regex EntireEmptyLineRegex();

        [GeneratedRegex(@"^(?!\n)\s*<#")]
        public static partial Regex DocumentationStartRegex();

        [GeneratedRegex(@"^(?!\n)\s*#>")]
        public static partial Regex DocumentationEndRegex();

        [GeneratedRegex(@"^(?!\n)\s*#.*$")]
        public static partial Regex EntireLineCommentRegex();

        [GeneratedRegex(@"(?!\n)\s*(?<!<)#(?!>).*$")]
        public static partial Regex EndOfLineComment();

        public static IEnumerable TestCases {
            get {
                yield return new TestCaseData(
                    new RegexUpdater(
                        50,
                        EntireLineCommentRegex(),
                        UpdateOptions.None,
                        _ => null
                    ),
                    """
                    # Comment
                    Write-Host 'Hello, World!';
                    Write-Host 'Goodbye, World!'; # Comment
                    """
                ).Returns("""
                Write-Host 'Hello, World!';
                Write-Host 'Goodbye, World!'; # Comment
                """).SetName("Removes Entire Line Comments");

                yield return new TestCaseData(
                    new RegexUpdater(
                        50,
                        EntireEmptyLineRegex(),
                        UpdateOptions.None,
                        _ => null
                    ),
                    """
                    Write-Host 'Hello, World!';

                    Write-Host 'Goodbye, World!';


                    # Comment


                    """
                ).Returns("""
                Write-Host 'Hello, World!';
                Write-Host 'Goodbye, World!';
                # Comment
                """).SetName("Remove Empty Lines");

                yield return new TestCaseData(
                    new PatternUpdater(
                        50,
                        DocumentationStartRegex(),
                        DocumentationEndRegex(),
                        UpdateOptions.None,
                        _ => []
                    ),
                    """
                    <#
                    .SYNOPSIS
                        This is a document block
                    #>
                    function foo {
                        Write-Host 'Hello, World!';
                    }
                    """
                ).Returns("""
                function foo {
                    Write-Host 'Hello, World!';
                }
                """).SetName("Remove Document Blocks");

                yield return new TestCaseData(
                    new RegexUpdater(
                        50,
                        EndOfLineComment(),
                        UpdateOptions.None,
                        _ => null
                    ),
                    """
                    Write-Host 'Hello, World!'; # Comment
                    Write-Host 'Goodbye, World!'; # Comment

                    <#
                    .SYNOPSIS
                        This is a document block
                    #>
                    function foo {
                        Write-Host 'Hello, World!';
                    }
                    """
                ).Returns("""
                Write-Host 'Hello, World!';
                Write-Host 'Goodbye, World!';

                <#
                .SYNOPSIS
                    This is a document block
                #>
                function foo {
                    Write-Host 'Hello, World!';
                }
                """).SetName("Remove Comments at the end of a line, after some code");
            }
        }
    }
}
