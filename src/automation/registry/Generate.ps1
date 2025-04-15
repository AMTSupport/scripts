#!ignore
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)]
        [String]$Path,

        [Parameter(Mandatory)]
        [String]$Key,

        [Parameter(Mandatory)]
        [AllowNull()]
        [Object]$Value,

        [Parameter(Mandatory)]
        [String]$Type,

        [Parameter()]
        [AllowNull()]
        [String]$ValidationBlock
    )

    $Before = <#ps1#> @"
`$Value = $(ConvertTo-InvokableValue $Value);
`$Type = $(ConvertTo-InvokableValue $Type);
`$Path = $(ConvertTo-InvokableValue $Path);
`$Key = $(ConvertTo-InvokableValue $Key);
`$CurrentValue = Get-RegistryKey -Path `$Path -Key `$Key -ErrorAction SilentlyContinue;
"@

    if ($null -eq $Value) {
        $Script = <#ps1#> @"
$Before
if ($(if ($ValidationBlock) { "-not ($ValidationBlock)" } else { '$null -ne $CurrentValue' })) {
    Invoke-Info "Deleting registry value: Path=`$Path, Key=`$Key"
    Remove-RegistryKey -Path `$Path -Key `$Key
} else {
    Invoke-Info "Registry value already removed: Path=`$Path, Key=`$Key"
}
"@
    } else {
        $Script = <#ps1#> @"
$Before
if ($(if ($ValidationBlock) { "-not ($ValidationBlock)" } else { '$CurrentValue -ne $Value' })) {
    Invoke-Info "Changing registry value: Path=`$Path, Key=`$Key, From=`$CurrentValue, To=`$Value"
    Set-RegistryKey -Path `$Path -Key `$Key -Value `$Value -Kind `$Type
} else {
    Invoke-Info "Registry value already set correctly: Path=`$Path, Key=`$Key, Value=`$Value"
}
"@
    }

    return $Script
}

function New-ScriptHereDoc {
    [CmdletBinding()]
    [OutputType([String])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$DetailsObject
    )

    $DetailsObject | Add-Member -MemberType NoteProperty -Name Output -Value 'None';
    # TODO - Just invocation of the script name with no parameters
    # $DetailsObject | Add-Member -MemberType NoteProperty -Name Example -Value 'None';

    $OrderOfDetails = @('Synopsis', 'Description', 'Output', 'Notes', 'Example', 'SeeAlso');
    $DetailsObjects = $OrderOfDetails | ForEach-Object {
        if ($DetailsObject.$_) {
            return ".{0}`n`t$($DetailsObject.$_ -replace "`n","`n`t")" -f $_.ToUpper()
        }
    }

    $Details = $DetailsObjects -join "`n`n";
    return "<#`n$Details`n#>";
}

<#
.SYNOPSIS
    Converts a JSON definition file into a list of registry actions.

.PARAMETER Definition
    The path to the JSON definition file.

.OUTPUTS
    System.Object[]
        The first element is the script heredoc. [String]
        The second element is a list of registry actions. [String[]]
#>
function Convert-RegistryDefinition {
    [CmdletBinding()]
    [OutputType([Object[]])]
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

        $Action = New-RegistryAction -Path $Entry.Path -Key $Entry.Key -Value $Entry.Value -Type $Entry.Type -ValidationBlock $Entry.ValidationBlock
        $Actions.Add($Action)
    }
    Invoke-Verbose "Processed $($Actions.Count) registry actions."

    $HereDoc = New-ScriptHereDoc -DetailsObject $Definitions.Details
    return $HereDoc, $Actions;
}

# TODO - Nested folder support
# TODO - Add hash of definition to prevent reprocessing
Invoke-RunMain $PSCmdlet {
    if (-not (Test-Path -Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory | Out-Null
    }

    $Disclaimer = '#!ignore WARNING! This script is auto-generated by Generate.ps1 from the definition {0}, do not edit manually.'
    $TemplateContent = Get-Content -Path $Template -Raw;

    $SrcToRoot = Resolve-Path -Path $PSScriptRoot/../.. -Relative -RelativeBasePath $PSScriptRoot/generated;
    $TemplateContent = $TemplateContent -replace $SRC_MARKER, $SrcToRoot;

    $Tokens = $null;
    $TemplateAst = [System.Management.Automation.Language.Parser]::ParseInput($TemplateContent, [ref]$Tokens, [ref]$null);

    $ScriptHereDoc = $Tokens | Where-Object { $_.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment } | Select-Object -First 1;
    if ($ScriptHereDoc.Extent.EndOffset -gt $TemplateAst.ParamBlock.Extent.StartOffset) {
        Invoke-Error "Template does not contain the required script heredoc." -Throw;
    }

    $JsonFiles = Get-ChildItem -Path $DefinitionPath -Filter '*.json?' -File;
    if ($JsonFiles.Count -eq 0) {
        Invoke-Warn "No definition files found in $DefinitionPath"
        return
    }

    $IndexOfRegEdits = $TemplateContent.IndexOf($REGISTRY_EDIT_MARKER);
    if ($IndexOfRegEdits -eq -1) {
        Invoke-Error "Template does not contain the marker $REGISTRY_EDIT_MARKER" -Throw;
    }

    foreach ($JsonFile in $JsonFiles) {
        #region Process JSON file
        $RelativePath = Resolve-Path -Path $JsonFile.FullName -Relative -RelativeBasePath $DefinitionPath;
        ($HereDoc, $Actions) = Convert-RegistryDefinition -Definition $JsonFile.FullName;
        #endregion

        $ScriptContent = [System.Text.StringBuilder]::new()

        #region Disclaimer & HereDoc
        $ScriptContent.AppendLine($Disclaimer -f $RelativePath) | Out-Null;
        if ($ScriptHereDoc.Extent.StartOffset -gt 0) {
            $ScriptContent.AppendLine($TemplateContent.Substring(0, $ScriptHereDoc.Extent.StartOffset)) | Out-Null;
        }
        Invoke-Debug "Adding heredoc: $HereDoc"
        $ScriptContent.AppendLine($HereDoc) | Out-Null;
        #endregion

        #region Actions
        $TemplateBeforeActions = $TemplateContent.Substring($ScriptHereDoc.Extent.EndOffset + 1, $IndexOfRegEdits - $ScriptHereDoc.Extent.EndOffset - 1);
        $ScriptContent.Append($TemplateBeforeActions) | Out-Null;

        $ActionLine = $TemplateBeforeActions -split "`n" | Select-Object -Last 1;
        $IndentLevel = $ActionLine.Length - $ActionLine.TrimStart().Length;
        $Indent = ' ' * $IndentLevel
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
        #endregion

        Invoke-Verbose "Processing complete for $JsonFile"
        $OutputScript = Join-Path -Path $OutputPath -ChildPath ($JsonFile.BaseName + '.ps1');
        $ScriptContent.ToString() | Set-Content -Path $OutputScript -Encoding UTF8;
        Invoke-Verbose "Registry script generated at $OutputScript"
    }

    Invoke-Verbose "All JSON files processed successfully."
}
