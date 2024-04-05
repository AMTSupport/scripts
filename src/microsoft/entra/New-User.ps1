Using 

function Get-RandomPassword {

}

function New-User {

}

Import-Module $PSScriptRoot/../../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    Invoke-EnsureModule -Modules 'Graph' -Scopes '';


};
