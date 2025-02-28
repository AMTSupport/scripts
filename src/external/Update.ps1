#!ignore

Using module ..\common\Environment.psm1
Using module ..\common\Logging.psm1
Using module ..\common\Scope.psm1
Using module ..\common\Utils.psm1
Using module ..\common\Input.psm1

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

    [Parameter(ParameterSetName = 'Patch')]
    [ValidateNotNullOrEmpty()]
    [String]$Patches = ($PSScriptRoot + '/patches/'),

    [Parameter(ParameterSetName = 'Update')]
    [Switch]$Force,

    [Parameter(ParameterSetName = 'Validate')]
    [Switch]$Validate,

    [Parameter(ParameterSetName = 'Patch')]
    [Switch]$CreatePatches
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
        if (Test-Path -Path $Path -PathType Leaf) {
            Remove-Item -Path $Path -Force;
        }

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

        $Hash = $Request.Headers['ETag'];
        $ContextLine = "#!ignore $Hash";

        try {
            if (Invoke-ApplyPatch -OutputPath $OutputPath -Patches $Patches) {
                $Content = Get-Content -Path $OutputPath -Raw;
                $ContextLine += "[$($Patches -join ', ')]";
            }
        } catch {
            Invoke-Error "Failed to apply patches to $($OutputPath).";
            $PSCmdlet.ThrowTerminatingError($_);
        }

        $ContextLine += "`n";
        $IgnoreAndHash = $Encoding.GetBytes($ContextLine);
        [Byte[]]$Content = Remove-EncodingBom $Encoding.GetBytes($Content) $Encoding;
        $Content = $IgnoreAndHash + $Content;
        Out-WithEncoding -Path $OutputPath -ContentBytes $Content -Encoding $Encoding;
    }
}

function Invoke-ApplyPatch {
    [OutputType([Bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$OutputPath,

        [Parameter()]
        [String[]]$Patches
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $OutputPath = Join-Path -Path $Output -ChildPath $Definition.Output;

        if ($Patches -and $Patches.Length -gt 0) {
            Invoke-Info "Applying patches to $($OutputPath).";
            $applyResult = git apply --no-index --ignore-space-change $Patches 2>&1
            if ($LASTEXITCODE -ne 0) {
                Invoke-Error "Failed to apply patches: $applyResult"
                $ErrorRecord = New-Object System.Management.Automation.ErrorRecord `
                              (New-Object System.Exception($applyResult), "PatchApplicationFailed", `
                              [System.Management.Automation.ErrorCategory]::InvalidOperation, $Patches)
                $PSCmdlet.ThrowTerminatingError($ErrorRecord);
            }

            return $True;
        }

        return $False;
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

function New-ScriptPatches {
    [CmdletBinding()]
    [OutputType([Void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.IO.FileInfo[]]$Definitions,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Patches
    )

    # If the working tree is dirty, fail and ask the user to commit or stash their changes.
    if (git status --porcelain) {
        Invoke-Error "Working tree is dirty, please commit or stash your changes.";
        exit 1;
    }

    if (-not (Test-Path -Path $Patches -PathType Container)) {
        New-Item -Path $Patches -ItemType Directory -Force;
    }

    # Remove the first line from each script, which contains the hash of the remote file. to get the original content.
    $Scripts = Get-ChildItem -Path $Output -Filter '*.ps1' -File -Recurse;
    foreach ($Script in $Scripts) {
        $Encoding = Get-ContentEncoding -Path $Script.FullName;
        $Content = Get-Content -Path $Script.FullName -Raw;
        $Content = $Content.Substring($Content.IndexOf("`n") + 1);
        Out-WithEncoding -Path $Script.FullName -Content $Content -Encoding $Encoding;
    }

    git add $Output

    $Continue = Get-UserConfirmation -Title 'Patch Creation' -Question 'Make your changes then press ''Yes'' to continue, or ''No'' to abort.';
    if (-not $Continue) {
        git reset --hard;
        exit;
    }

    foreach ($RawDefinition in $Definitions) {
        $Definition = Get-Content -Path $RawDefinition.FullName | ConvertFrom-Json;

        if (-not $Definition.Source -or -not $Definition.Output) {
            Invoke-Error "Invalid definition file $($RawDefinition.Name).";
            continue;
        }

        $OutputPath = $Output + $Definition.Output;
        if (-not (Test-Path -Path $OutputPath -PathType Leaf)) {
            Invoke-Warn "Output file $($OutputPath) does not exist, skipping...";
            continue;
        }

        if (git diff $OutputPath) {
            $LeafName = Split-Path -Path $OutputPath -Leaf;
            $PatchName = Get-UserInput -Title 'Patch Name' -Question "Please provide a name for the patch for $($Definition.Output).";
            $PatchName = Join-Path -Path $Patches -ChildPath ("${LeafName}_${PatchName}.patch");
            git diff $OutputPath > $PatchName;

            $Definition.Patches += $PatchName;
            $Definition | ConvertTo-Json | Set-Content -Path $RawDefinition.FullName;

            git add $PatchName;
            git add $RawDefinition.FullName;
            Invoke-Info "Patch created at $PatchName.";

            git checkout HEAD -- $OutputPath;
            try {
                Invoke-ApplyPatch -OutputPath $OutputPath -Patches $Definition.Patches;
            } catch {
                Invoke-Error "Failed to apply patch to $($OutputPath).";
                $PSCmdlet.ThrowTerminatingError($_);
            }
        } else {
            Invoke-Info "No changes detected for $($Definition.Output), skipping patch creation.";
            git checkout HEAD -- $OutputPath;
        }
    }
}

Invoke-RunMain $PSCmdlet {
    $Definitions = Resolve-Path -Path $Definitions;
    $Output = Resolve-Path -Path $Output;
    $Patches = Resolve-Path -Path $Patches;
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

    if ($PSCmdlet.ParameterSetName -eq 'Patch') {
        New-ScriptPatches -Definitions $WantedDefinitions -Patches $Patches;
    }
};
