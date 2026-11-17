Using module ../Output/PowerShellModules/AMT.PowerShell.Common/AMT.PowerShell.Common.psd1

[CmdletBinding()]
param()

Invoke-RunMain $PSCmdlet {
    [Compiler.Analyser.SuppressAnalyserAttribute(
        'UseOfUndefinedFunction',
        'thiscommand'
    )]
    param()

    Write-Error 'This is an error message!' -Category InvalidOperation;
    Invoke-FailedExit 1050;

    thiscommand;
}
