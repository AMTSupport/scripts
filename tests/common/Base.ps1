$VerbosePreference = 'Continue';
$DebugPreference = 'Continue';
Import-Module -Name $PSScriptRoot/../../src/common/Environment.psm1;

if ((Get-PSCallStack)[3].Command -or -not ((Get-PSCallStack)[0].Command -match "<ScriptBlock>|$($PSCommandPath | Split-Path -Leaf)")) {
    $Local:ModuleName = ((Get-PSCallStack)[0].InvocationInfo.PSCommandPath | Split-Path -LeafBase) -replace '\.Tests$', '';
    Import-Module -Name "$PSScriptRoot/../../src/common/$Local:ModuleName.psm1";

    if (-not (Get-Module -Name $Local:ModuleName)) {
        throw "Module $Local:ModuleName is not available.";
    }
}

return $Local:ModuleName;
