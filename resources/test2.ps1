Using module ../src/common/00-Environment.psm1
Using module ../src/common/01-Logging.psm1
Using module ../src/common/02-Exit.psm1

[CmdletBinding()]
param()

Invoke-RunMain $PSCmdlet {
    Write-Error 'This is an error message!' -Category InvalidOperation;
    Invoke-FailedExit 1050;
}
