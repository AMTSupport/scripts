#!ignore

Using module ..\common\Environment.psm1
Using module ..\common\Logging.psm1
Using module ..\common\Scope.psm1
Using module ..\common\Utils.psm1

<#
.SYNOPSIS
    Update the external scripts.

.PARAMETER Definitions
    Where to find the script definitions.

.PARAMETER Output
    Where to save the scripts to.

.PARAMETER Force
    Force the update of the scripts even if the hash matches remote.
#>
[CmdletBinding(DefaultParameterSetName = 'Update')]
param(
    [Parameter(ParameterSetName = 'Update')]
    [Parameter(ParameterSetName = 'Validate')]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [String]$Definitions = ($PSScriptRoot + '/sources/'),

    [Parameter(ParameterSetName = 'Update')]
    [Parameter(ParameterSetName = 'Validate')]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [String]$Output = ($PSScriptRoot + '/scripts/'),

    [Parameter(ParameterSetName = 'Update')]
    [Switch]$Force,

    [Parameter(ParameterSetName = 'Validate')]
    [Switch]$Validate
)

function Compare-LocalToRemote {
    [OutputType([Boolean])]
    param(
        [String]$LocalFile,
        [String]$RemoteURI
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        if (-not (Test-Path -Path $LocalFile -PathType Leaf)) {
            return $False;
        }

        # In the LocalFile we store a hash of the raw remote file we downloaded, its on the first line after #!ignore
        $LocalHash = (Get-Content -Path $LocalFile -TotalCount 1).Substring(9);
        $RemoteHash = (Invoke-WebRequest -Uri $RemoteURI -Method Head).Headers['ETag'];

        return $LocalHash -eq $RemoteHash;
    }
}

function Out-WithEncoding {
    [OutputType([Void])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Content')]
        [Parameter(Mandatory, ParameterSetName = 'ContentBytes')]
        [String]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Content')]
        [String]$Content,

        [Parameter(Mandatory, ParameterSetName = 'ContentBytes')]
        [Byte[]]$ContentBytes,

        [Parameter(Mandatory, ParameterSetName = 'Content')]
        [Parameter(Mandatory, ParameterSetName = 'ContentBytes')]
        [System.Text.Encoding]$Encoding
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $WriteStream = [System.IO.File]::OpenWrite($Path);
        if ($Encoding.GetPreamble().Length -gt 0) {
            $WriteStream.Write($Encoding.GetPreamble(), 0, $Encoding.GetPreamble().Length);
        }

        $Bytes = if ($PSCmdlet.ParameterSetName -eq 'ContentBytes') {
            $ContentBytes;
        } else {
            $Encoding.GetBytes($Content);
        }

        $Bytes = Remove-EncodingBom $Bytes $Encoding;
        $WriteStream.Write($Bytes, 0, $Bytes.Length);
        $WriteStream.Close();
    }
}

function Get-RemoteAndPatch {
    param(
        [String]$RemoteURI,
        [String]$OutputPath,
        [String[]]$Patches
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $Request = Invoke-WebRequest -Uri $RemoteURI -Method Get;

        [String]$Content = '';
        [String]$Encoding = [System.Text.Encoding]::UTF8;
        if ($Request.Headers['Content-Type'] -eq 'application/octet-stream') {
            [System.Text.Encoding]$Encoding = Get-ContentEncoding -ContentBytes $Request.Content;
            $Content = $Encoding.GetString($Request.Content);
        } else {
            $Content = $Request.Content;
        }

        Out-WithEncoding -Path $OutputPath -Content $Content -Encoding $Encoding;

        if ($Patches -and $Patches.Length -gt 0) {
            Invoke-Info "Applying patches to $($OutputPath).";
            git apply $Patches
            $Content = Get-Content -Path $OutputPath -Raw;
        }

        $Hash = $Request.Headers['ETag'];
        $IgnoreAndHash = $Encoding.GetBytes("#!ignore $Hash`n");
        [Byte[]]$Content = Remove-EncodingBom $Encoding.GetBytes($Content) $Encoding;
        $Content = $IgnoreAndHash + $Content;
        Out-WithEncoding -Path $OutputPath -ContentBytes $Content -Encoding $Encoding;
    }
}

function Test-ScriptsAreParsable {
    [OutputType([Bool])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'RecursiveDirectory')]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [String]$Path,

        [Parameter(Mandatory, ParameterSetName = 'ExplicitFiles')]
        [String[]]$Files
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $Scripts = if ($PSCmdlet.ParameterSetName -eq 'RecursiveDirectory') {
            Get-ChildItem -Path $Path -Filter '*.ps1' -File -Recurse;
        } else {
            $Files | ForEach-Object { Get-Item -Path $_; };
        }

        $HadErrors = $False;
        foreach ($Script in $Scripts) {
            Invoke-Info "Parsing $($Script.Name).";
            [System.Management.Automation.Language.ParseError[]]$Errors = $null;
            $null = [System.Management.Automation.Language.Parser]::ParseFile($Script.FullName, [ref]$null, [ref]$Errors);

            if ($Errors) {
                $HadErrors = $True;
                Invoke-Error "Failed to parse $($Script.Name) with $($Errors.Count) errors.";
                foreach ($ParserError in $Errors) {
                    Format-Error -ErrorRecord $ParserError;
                }
            }
        }

        return -not $HadErrors;
    }
}

Invoke-RunMain $PSCmdlet {
    $Definitions = Resolve-Path -Path $Definitions;
    $Output = Resolve-Path -Path $Output;
    $WantedDefinitions = Get-ChildItem -Path $Definitions -Filter '*.json?' -File -Recurse;

    if ($PSCmdlet.ParameterSetName -eq 'Update') {
        $FilesForValidation = @();
        foreach ($RawDefinition in $WantedDefinitions) {
            Invoke-Info "Processing $($RawDefinition.Name).";
            $Definition = Get-Content -Path $RawDefinition.FullName | ConvertFrom-Json;

            if (-not $Definition.Source -or -not $Definition.Output) {
                Invoke-Error "Invalid definition file $($RawDefinition.Name).";
                continue;
            }

            Invoke-Debug "Processing $($Definition.Output).";
            $OutputPath = $Output + $Definition.Output;

            $OutputDirectory = Split-Path -Path $OutputPath;
            if (-not (Test-Path -Path $OutputDirectory -PathType Container)) {
                $null = New-Item -Path $OutputDirectory -ItemType Directory -Force;
            }

            if (-not $Force -and (Compare-LocalToRemote -LocalFile $OutputPath -RemoteURI $Definition.Source)) {
                Invoke-Info "No update required for $($Definition.Output).";
                continue;
            }

            Get-RemoteAndPatch -RemoteURI $Definition.Source -OutputPath $OutputPath -Patches $Definition.Patches;
            $FilesForValidation += $OutputPath;
        }

        if ($FilesForValidation.Length -gt 0) {
            if (-not (Test-ScriptsAreParsable -Files $FilesForValidation)) {
                exit 1
            };
        }
    }

    if ($PSCmdlet.ParameterSetName -eq 'Validate') {
        Invoke-Info "Validating scripts in $($Output).";
        if (-not (Test-ScriptsAreParsable -Path $Output)) {
            exit 1
        }
    }
};
