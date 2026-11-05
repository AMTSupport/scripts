<#
.SYNOPSIS
    This is a template file for the generated registry scripts.

.NOTES
    The marker <#REGISTRY_EDITS#\> will be replaced with the content for changing the registry.
    The marker <#SRC#\> will be replaced with the scripts location to src.
#>

using module <#SRC#>\..\Output\PowerShellModules\AMT.PowerShell.Common\AMT.PowerShell.Common.psd1

[CmdletBinding()]
param(<#REGISTRY_PARAMETERS#>)

Invoke-RunMain $PSCmdlet {
    Invoke-EnsureAdministrator;

    <#REGISTRY_EDITS#>
}
