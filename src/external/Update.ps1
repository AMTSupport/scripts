#!ignore

Using module '../common/Environment.psm1'
Using module '../common/Logging.psm1'
Using module '../common/Scope.psm1'

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
[CmdletBinding()]
param(
    [String]$Definitions = ($PSScriptRoot + './sources/'),

    [String]$Output = ($PSScriptRoot + './scripts/'),

    [Switch]$Force
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

        [String]$Content;
        if ($Request.Headers['Content-Type'] -eq 'application/octet-stream') {
            $Content = [System.Text.Encoding]::UTF8.GetString($Request.Content);
        } else {
            $Content = $Request.Content;
        }
        $Content | Out-File -FilePath $OutputPath -Force;

        if ($Patches -and $Patches.Length -gt 0) {
            Invoke-Info "Applying patches to $($OutputPath).";
            # $Command = "git apply --verbose $Patches";
            # Invoke-Debug "Running: $Command";
            # Invoke-Expression $Command;
            git apply $Patches
            $Content = Get-Content -Path $OutputPath -Raw;
        }

        $Hash = $Request.Headers['ETag'];
        $Content = "#!ignore $Hash`n$Content";
        $Content | Out-File -FilePath $OutputPath -Force;
    }
}

Invoke-RunMain $PSCmdlet {
    $WantedDefinitions = Get-ChildItem -Path $Definitions -Filter '*.json?' -File;

    foreach ($RawDefinition in $WantedDefinitions) {
        Invoke-Info "Processing $($RawDefinition.Name).";
        $Definition = Get-Content -Path $RawDefinition.FullName | ConvertFrom-Json;

        if (-not $Definition.Source -or -not $Definition.Output) {
            Invoke-Error "Invalid definition file $($RawDefinition.Name).";
            continue;
        }

        Invoke-Debug "Processing $($Definition.Output).";
        $OutputPath = $Output + $Definition.Output;

        if (-not $Force -and (Compare-LocalToRemote -LocalFile $OutputPath -RemoteURI $Definition.Source)) {
            Invoke-Info "No update required for $($Definition.Output).";
            continue;
        }

        Get-RemoteAndPatch -RemoteURI $Definition.Source -OutputPath $OutputPath -Patches $Definition.Patches;
    }
};
