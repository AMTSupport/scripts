<#
.SYNOPSIS
    Generates a PowerShell script to apply registry changes defined in JSON.

.DESCRIPTION
    This script reads JSON files from a folder and generates PowerShell scripts to apply the registry changes.

.PARAMETER DefinitionPath
    The container where the JSON definition files are located.

.PARAMETER OutputPath
    The container to save the generated PowerShell scripts.

.PARAMETER Template
    The template to use for the generated scripts.
    This template should contain the markers <#REGISTRY_EDITS#\> and <#SRC#\>.

.OUTPUTS
    System.Void
#>

using module ..\..\common\Logging.psm1
using module ..\..\common\Registry.psm1
using module ..\..\common\Environment.psm1
using module ..\..\common\Utils.psm1

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [String]$DefinitionPath = "$PSScriptRoot/definitions",

    [Parameter()]
    [String]$OutputPath = "$PSScriptRoot/generated",

    [Parameter()]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [String]$Template = "$PSScriptRoot/../../../resources/templates/Registry.ps1"
)

$REGISTRY_EDIT_MARKER = '<#REGISTRY_EDITS#>'
$SRC_MARKER = '<#SRC#>'

<#
.SYNOPSIS
    Creates the powershell code to apply a registry change.

.PARAMETER Path
    The registry path to modify.

.PARAMETER Name
    The name of the registry value to modify.

.PARAMETER Value
    The value to set.

.PARAMETER Type
    The type of the registry value to set.

.OUTPUTS
    System.String
#>
function New-RegistryAction {
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory)]
        [String]$Path,

        [Parameter(Mandatory)]
        [String]$Key,

        [Parameter(Mandatory)]
        [AllowNull()]
        [Object]$Value,

        [Parameter(Mandatory)]
        [String]$Type
    )

    $Before = @"
`$Value = $(ConvertTo-InvokableValue $Value);
`$Type = $(ConvertTo-InvokableValue $Type);
`$Path = $(ConvertTo-InvokableValue $Path);
`$Key = $(ConvertTo-InvokableValue $Key);
Get-RegistryKey -Path `$Path -Name `$Key -ErrorAction SilentlyContinue;
"@

    if ($null -eq $Value) {
        $Script = @"
$Before
if ($null -ne `$CurrentValue) {
    Invoke-Verbose "Deleting registry value: Path=`$Path, Name=`$Key"
    Remove-RegistryKey -Path `$Path -Key `$Key
} else {
    Invoke-Verbose "Registry value already removed: Path=`$Path, Name=`$Key"
}
"@
    } else {
        $Script = @"
$Before
if (`$CurrentValue -ne `$Value) {
    Invoke-Verbose "Changing registry value: Path=`$Path, Name=`$Key, From=`$CurrentValue, To=`$Value"
    Set-RegistryKey -Path `$Path -Key `$Key -Value `$Value -Type `$Type
} else {
    Invoke-Verbose "Registry value already set correctly: Path=`$Path, Name=`$Key, Value=`$Value"
}
"@
    }

    return $Script
}

<#
.SYNOPSIS
    Converts a JSON definition file into a list of registry actions.

.PARAMETER Definition
    The path to the JSON definition file.

.OUTPUTS
    System.Collections.Generic.List[System.String]
#>
function Convert-RegistryDefinition {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[System.String]])]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ (Test-Path -Path $_ -PathType Leaf) -and ($_ -match '\.jsonc?$') })]
        [String]$Definition
    )

    $Actions = [System.Collections.Generic.List[System.String]]::new()
    $Definitions = Get-Content -Path $Definition -Raw | ConvertFrom-Json

    foreach ($Entry in $Definitions.Entries) {
        if ($null -eq $Entry.Path -or $null -eq $Entry.Key) {
            Invoke-Warn "Missing required properties in entry: $($Entry | ConvertTo-Json)"
            continue
        }

        $Action = New-RegistryAction -Path $Entry.Path -Key $Entry.Key -Value $Entry.Value -Type $Entry.Type
        $Actions.Add($Action)
    }


    Invoke-Verbose "Processed $($Actions.Count) registry actions."
    return $Actions -join ([Environment]::NewLine)
}

# TODO - Nested folder support
# TODO - Add hash of definition to prevent reprocessing
Invoke-RunMain $PSCmdlet {
    if (-not (Test-Path -Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory | Out-Null
    }

    $TemplateContent = Get-Content -Path $Template -Raw;
    $JsonFiles = Get-ChildItem -Path $DefinitionPath -Filter '*.json?' -File
    $DefinitionPathRelativeToRoot = Resolve-Path -Path $DefinitionPath -Relative -RelativeBasePath $PSScriptRoot/../..;
    $SrcToRoot = Resolve-Path -Path $PSScriptRoot/../.. -Relative -RelativeBasePath $PSScriptRoot/generated;
    $TemplateContent = $TemplateContent -replace $SRC_MARKER, $SrcToRoot;
    $Disclaimer = @"
#!ignore
# This script is auto-generated from Generate.ps1 using the definitions in $DefinitionPathRelativeToRoot
"@;

    if ($JsonFiles.Count -eq 0) {
        Invoke-Warn "No definition files found in $DefinitionPath"
        return
    }

    foreach ($JsonFile in $JsonFiles) {
        $Actions = Convert-RegistryDefinition -Definition $JsonFile.FullName

        $ScriptContent = [System.Text.StringBuilder]::new()
        $ScriptContent.AppendLine($Disclaimer) | Out-Null;
        $ScriptContent.AppendLine("# Script generated from $JsonFile") | Out-Null;

        $IndexOfRegEdits = $TemplateContent.IndexOf($REGISTRY_EDIT_MARKER);
        if ($IndexOfRegEdits -eq -1) {
            Invoke-Warn "Template does not contain the marker $REGISTRY_EDIT_MARKER"
            exit 1
        }

        $IndentLevel = ($TemplateContent.Substring(0, $IndexOfRegEdits) -split "`n" | Select-Object -Last 1).Length - ($TemplateContent.Substring(0, $IndexOfRegEdits) -split "`n" | Select-Object -Last 1).TrimStart().Length
        $Indent = ' ' * $IndentLevel

        $ScriptContent.Append($TemplateContent.Substring(0, $IndexOfRegEdits)) | Out-Null;
        $FirstLine = $True;
        $Actions -split "`n" | ForEach-Object {
            if ($FirstLine) {
                $FirstLine = $False;
            } else {
                $ScriptContent.Append($Indent) | Out-Null;
            }

            $ScriptContent.AppendLine($_) | Out-Null;
        }
        $ScriptContent.Append($TemplateContent.Substring($IndexOfRegEdits + $REGISTRY_EDIT_MARKER.Length)) | Out-Null;
        $OutputScript = Join-Path -Path $OutputPath -ChildPath ($JsonFile.BaseName + '.ps1');

        Invoke-Verbose "Processing complete for $JsonFile"
        $ScriptContent.ToString() | Set-Content -Path $OutputScript -Encoding UTF8;
        Invoke-Verbose "Registry script generated at $OutputScript"
    }

    Invoke-Verbose "All JSON files processed successfully."
}
