using System.Collections;
using System.Text.RegularExpressions;
using Text;
using Text.Updater;

namespace Compiler.Test;

[TestFixture]
public class CompiledScriptTest
{
    const string TEST_SCRIPT = /*ps1*/ """
    #Requires -Version 5.1

    Using module ../src/common/00-Environment.psm1;
    # Using module @{
    #     ModuleName      = 'PSReadLine';
    #     RequiredVersion = '2.3.5';
    # }

    <#
        Making some random documentation for the module here!!
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name
    )

    Set-StrictMode -Version 3;

    Import-Module $PSScriptRoot/../src/common/00-Environment.psm1;
    Invoke-RunMain $MyInvocation {
        Write-Host 'Hello, World!';

        Write-Host @"
            This is a multiline string!
            It can have multiple lines!
    @";

        # Write-Error 'This is an error message!' -Category InvalidOperation;
        Invoke-FailedExit 1050;

        # Random comment
        $Restart = Get-UserConfirmation 'Restart' 'Do you want to restart the script?';
        if ($Restart) {
            Write-Host 'Restarting script...';
            Restart-Script; # Comment at the end of a line!!
        }
        else {
            Write-Host 'Exiting script...';
        };
    }
    """;

    [TestCaseSource(typeof(TestData), nameof(TestData.TestCases))]
    public string Test(
        TextSpanUpdater updater
    )
    {
        var document = new TextEditor(new TextDocument(TEST_SCRIPT.Split('\n')))!;
        document.AddEdit(() => updater);

        document.ApplyEdits();
        return document.GetContent();
    }

    [TestCaseSource(typeof(TestData), nameof(TestData.ExtractParameterBlockCases))]
    public string? ExtractParameterBlock(
        bool expectNull,
        string scriptText
    )
    {
        var scriptLines = scriptText.Split('\n');
        var script = new CompiledScript("test", scriptLines);

        var result = script.ExtractParameterBlock();

        Assert.Multiple(() =>
        {
            if (expectNull)
            {
                Assert.That(result, Is.Null);
            }
            else
            {
                Assert.That(result, Is.Not.Null);
            }
        });

        return result?.Extent.Text;
    }


    public static class TestData
    {
        public static IEnumerable ExtractParameterBlockCases
        {
            get
            {
                yield return new TestCaseData(false, TEST_SCRIPT).Returns("""
                param(
                    [Parameter()]
                    [string]$Name
                )
                """).SetName("ExtractParameterBlock_ReturnsParameterBlockAst_WhenParameterBlockExists");

                yield return new TestCaseData(true, """
                #Requires -Version 5.1

                Write-Host 'Hello, World!';
                """).Returns(null).SetName("ExtractParameterBlock_ReturnsNull_WhenParameterBlockDoesNotExist");

                yield return new TestCaseData(true, "").Returns(null).SetName("ExtractParameterBlock_ReturnsNull_WhenScriptIsEmpty");

                yield return new TestCaseData(false, "param()").Returns("param()").SetName("ExtractParameterBlock_ReturnsParameterBlockAst_WhenExistsWithoutAttributesAndParameters");

                yield return new TestCaseData(false, "param([string]$Name)").Returns("param([string]$Name)").SetName("ExtractParameterBlock_ReturnsParameterBlockAst_WhenExistsWithAttributesAndParameters");

                yield return new TestCaseData(false, "param([string]$Name, [int]$Age)").Returns("param([string]$Name, [int]$Age)").SetName("ExtractParameterBlock_ReturnsParameterBlockAst_WhenExistsWithMultipleParameters");
            }
        }

        public static IEnumerable TestCases
        {
            get
            {
                yield return new TestCaseData(
                    new PatternUpdater(
                        new Regex(@"^\s*<#"),
                        new Regex(@"^\s*#>"),
                        UpdateOptions.None,
                        (lines) =>
                        {
                            var startIndex = 0;

                            // If the multiline is not at the start of the content it does not need to be trimmed, so we skip it.
                            var trimmedLine = lines[0].Trim();
                            if (trimmedLine.StartsWith(@"@""") || trimmedLine.StartsWith("@'"))
                            {
                                startIndex++;
                            }

                            // Get the multiline indent level from the last line of the string.
                            // This is used so we don't remove any whitespace that is part of the actual string formatting.
                            var indentLevel = new Regex(@"^\s*").Match(lines.Last()).Value.Length;

                            var updatedLines = lines.Select((line, index) =>
                            {
                                if (index < startIndex)
                                {
                                    return line;
                                }

                                return line[indentLevel..];
                            });

                            return updatedLines.ToArray();
                        }
                    )
                ).Returns("""
                #Requires -Version 5.1

                Using module ../src/common/00-Environment.psm1;
                # Using module @{
                #     ModuleName      = 'PSReadLine';
                #     RequiredVersion = '2.3.5';
                # }

                <#
                    Making some random documentation for the module here!!
                #>
                [CmdletBinding()]
                param(
                    [Parameter()]
                    [string]$Name
                )

                Set-StrictMode -Version 3;

                Import-Module $PSScriptRoot/../src/common/00-Environment.psm1;
                Invoke-RunMain $MyInvocation {
                    Write-Host 'Hello, World!';

                    Write-Host @"
                        This is a multiline string!
                        It can have multiple lines!
                @";

                    # Write-Error 'This is an error message!' -Category InvalidOperation;
                    Invoke-FailedExit 1050;

                    # Random comment
                    $Restart = Get-UserConfirmation 'Restart' 'Do you want to restart the script?';
                    if ($Restart) {
                        Write-Host 'Restarting script...';
                        Restart-Script; # Comment at the end of a line!!
                    }
                    else {
                        Write-Host 'Exiting script...';
                    };
                }
                """).SetName("Test_UpdatesMultilineString");

                // FIXME - This captures the newline if previous line was empty
                // Fixing with a negative lookbehind assertion, but this is a hacky solution
                yield return new TestCaseData(
                    new RegexUpdater(
                        @"^(?!\n)\s*#.*$",
                        UpdateOptions.None,
                        _ => string.Empty
                    )
                ).Returns("""

                Using module ../src/common/00-Environment.psm1;

                <#
                    Making some random documentation for the module here!!
                [CmdletBinding()]
                param(
                    [Parameter()]
                    [string]$Name
                )

                Set-StrictMode -Version 3;

                Import-Module $PSScriptRoot/../src/common/00-Environment.psm1;
                Invoke-RunMain $MyInvocation {
                    Write-Host 'Hello, World!';

                    Write-Host @"
                        This is a multiline string!
                        It can have multiple lines!
                @";

                    Invoke-FailedExit 1050;

                    $Restart = Get-UserConfirmation 'Restart' 'Do you want to restart the script?';
                    if ($Restart) {
                        Write-Host 'Restarting script...';
                        Restart-Script; # Comment at the end of a line!!
                    }
                    else {
                        Write-Host 'Exiting script...';
                    };
                }
                """).SetName("Test_RemovesEntireLineComments");

                yield return new TestCaseData(
                    new RegexUpdater(
                        @"^\s*$",
                        UpdateOptions.None,
                        _ => string.Empty
                    )
                ).Returns("""
                #Requires -Version 5.1
                Using module ../src/common/00-Environment.psm1;
                # Using module @{
                #     ModuleName      = 'PSReadLine';
                #     RequiredVersion = '2.3.5';
                # }
                <#
                    Making some random documentation for the module here!!
                #>
                [CmdletBinding()]
                param(
                    [Parameter()]
                    [string]$Name
                )
                Set-StrictMode -Version 3;
                Import-Module $PSScriptRoot/../src/common/00-Environment.psm1;
                Invoke-RunMain $MyInvocation {
                    Write-Host 'Hello, World!';
                    Write-Host @"
                        This is a multiline string!
                        It can have multiple lines!
                @";
                    # Write-Error 'This is an error message!' -Category InvalidOperation;
                    Invoke-FailedExit 1050;
                    # Random comment
                    $Restart = Get-UserConfirmation 'Restart' 'Do you want to restart the script?';
                    if ($Restart) {
                        Write-Host 'Restarting script...';
                        Restart-Script; # Comment at the end of a line!!
                    }
                    else {
                        Write-Host 'Exiting script...';
                    };
                }
                """).SetName("Test_RemovesEmptyLines");

                yield return new TestCaseData(
                    new PatternUpdater(
                        new Regex(@"^\s*<#"),
                        new Regex(@"^\s*#>"),
                        UpdateOptions.None,
                        _ => []
                    )
                ).Returns("""
                #Requires -Version 5.1

                Using module ../src/common/00-Environment.psm1;
                # Using module @{
                #     ModuleName      = 'PSReadLine';
                #     RequiredVersion = '2.3.5';
                # }

                [CmdletBinding()]
                param(
                    [Parameter()]
                    [string]$Name
                )

                Set-StrictMode -Version 3;

                Import-Module $PSScriptRoot/../src/common/00-Environment.psm1;
                Invoke-RunMain $MyInvocation {
                    Write-Host 'Hello, World!';

                    Write-Host @"
                        This is a multiline string!
                        It can have multiple lines!
                @";

                    # Write-Error 'This is an error message!' -Category InvalidOperation;
                    Invoke-FailedExit 1050;

                    # Random comment
                    $Restart = Get-UserConfirmation 'Restart' 'Do you want to restart the script?';
                    if ($Restart) {
                        Write-Host 'Restarting script...';
                        Restart-Script; # Comment at the end of a line!!
                    }
                    else {
                        Write-Host 'Exiting script...';
                    };
                }
                """).SetName("Test_RemovesMultilineComments");

                yield return new TestCaseData(
                    new RegexUpdater(
                        @"(?!\n)\s*#.*$",
                        UpdateOptions.None,
                        _ => string.Empty
                    )
                ).Returns("""
                #Requires -Version 5.1

                Using module ../src/common/00-Environment.psm1;
                # Using module @{
                #     ModuleName      = 'PSReadLine';
                #     RequiredVersion = '2.3.5';
                # }

                <#
                    Making some random documentation for the module here!!
                #>
                [CmdletBinding()]
                param(
                    [Parameter()]
                    [string]$Name
                )

                Set-StrictMode -Version 3;

                Import-Module $PSScriptRoot/../src/common/00-Environment.psm1;
                Invoke-RunMain $MyInvocation {
                    Write-Host 'Hello, World!';

                    Write-Host @"
                        This is a multiline string!
                        It can have multiple lines!
                @";

                    # Write-Error 'This is an error message!' -Category InvalidOperation;
                    Invoke-FailedExit 1050;

                    # Random comment
                    $Restart = Get-UserConfirmation 'Restart' 'Do you want to restart the script?';
                    if ($Restart) {
                        Write-Host 'Restarting script...';
                        Restart-Script;
                    }
                    else {
                        Write-Host 'Exiting script...';
                    };
                }
                """).SetName("Test_RemovesCommentsAtEndOfLine");
            }
        }
    }
}
