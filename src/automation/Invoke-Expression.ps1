Using module ../../Output/PowerShellModules/AMT.PowerShell.Common/AMT.PowerShell.Common.psd1


[CmdletBinding()]
Param(
    [Parameter(Mandatory)]
    [ScriptBlock]$Expression
)

Invoke-RunMain $PSCmdlet {
    try {
        & $Expression;
    } catch {
        Invoke-FailedExit -ExitCode 1001 -ErrorRecord $_;
    }
};
