Using module ..\common\Environment.psm1
Using module ..\common\Exit.psm1

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
