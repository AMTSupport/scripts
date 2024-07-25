Param(
    [Parameter(Mandatory)]
    [ScriptBlock]$Expression
)

Import-Module $PSScriptRoot/../common/00-Environment.psm1;
Invoke-RunMain $PSCmdlet {
    try {
        & $Expression;
    } catch {
        Invoke-FailedExit -ExitCode 1001 -ErrorRecord $_;
    }
};
