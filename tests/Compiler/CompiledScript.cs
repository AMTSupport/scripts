using System.Collections;

namespace Compiler.Test;

[TestFixture]
public class CompiledScriptTest
{
    const string TEST_SCRIPT = /*ps1*/ @"
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
    ";

    [TestCaseSource(typeof(TestData), nameof(TestData.ExtractParameterBlockCases))]
    public string ExtractParameterBlock_ReturnsParameterBlockAst(
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

        return result.Extent.Text;
    }


    public static class TestData
    {
        public static IEnumerable ExtractParameterBlockCases
        {
            get
            {
                yield return new TestCaseData(false, TEST_SCRIPT).Returns(@"
                    [CmdletBinding()]
                    param(
                        [Parameter()]
                        [string]$Name
                    )
                ").SetName("ExtractParameterBlock_ReturnsParameterBlockAst_WhenParameterBlockExists");
            }
        }
    }
}
