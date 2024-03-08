$VerbosePreference = 'Continue';
$DebugPreference = 'Continue';
Import-Module -Name $PSScriptRoot/../../src/common/00-Environment.psm1;
Import-CommonModules;

if ((Get-PSCallStack)[3].Command -or -not ((Get-PSCallStack)[0].Command -match "<ScriptBlock>|$($PSCommandPath | Split-Path -Leaf)")) {
    $Local:ModuleName = ((Get-PSCallStack)[0].InvocationInfo.PSCommandPath | Split-Path -LeafBase) -replace '\.Tests$', '';

    if (-not (Get-Module -Name $Local:ModuleName)) {
        throw "Module $Local:ModuleName is not available.";
    }
}

return $Local:ModuleName;
