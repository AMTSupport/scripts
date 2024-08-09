Using module ../src/common/Environment.psm1
Using module ../src/common/Logging.psm1
Using module ../src/common/Exit.psm1

[CmdletBinding()]
param()

Invoke-RunMain $PSCmdlet {
    Write-Error 'This is an error message!' -Category InvalidOperation;
    Invoke-FailedExit 1050;
}
