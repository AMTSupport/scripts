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
    [CmdletBinding()]
    [OutputType([Boolean])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$LocalFile,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$RemoteURI
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        if (-not (Test-Path -Path $LocalFile -PathType Leaf)) {
            return $False;
        }

        $LocalHash = Get-Context -Path $LocalFile | Select-Object -ExpandProperty Hash;
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

function Out-WithContextAndEncoding {
    [OutputType([Void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Content,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.Text.Encoding]$Encoding,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCustomObject]$Context
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [String[]]$ContentSplit = $Content -split "`n";
        if ($ContentSplit[0].StartsWith('#!ignore')) {
            $Content = ($ContentSplit | Select-Object -Skip 1) -join "`n";
        }

        $Context.Patches = $Context.Patches | ForEach-Object {
            Resolve-Path -Relative -RelativeBasePath $PSScriptRoot -Path $_;
        }

        $ContextLine = "#!ignore $($Context | ConvertTo-Json -Compress)`n";
        $IgnoreAndHash = $Encoding.GetBytes($ContextLine);
        [Byte[]]$Content = Remove-EncodingBom $Encoding.GetBytes($Content) $Encoding;
        $Content = $IgnoreAndHash + $Content;
        Out-WithEncoding -Path $Path -ContentBytes $Content -Encoding $Encoding;
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

        [String]$Hash = $Request.Headers['ETag'];
        # Drop the quotes from the string
        $Hash = $Hash.Substring(1, $Hash.Length - 2);
        $Context = New-Context -Hash $Hash -OutputPath $OutputPath -Patches $Patches;
        Out-WithContextAndEncoding `
            -Path $OutputPath `
            -Context $Context `
            -Content $Content `
            -Encoding $Encoding;

        try {
            Invoke-ApplyPatch -OutputPath $OutputPath -Patches $Patches;
        } catch {
            Invoke-Error "Failed to apply patches to $($OutputPath).";
            $PSCmdlet.ThrowTerminatingError($_);
        }
    }
}

function Invoke-ApplyPatch {
    [CmdletBinding()]
    [OutputType([Void])]
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
        $Context = Get-Context -Path $OutputPath;
        if ($null -eq $Context.Patches) { $Context | Add-Member -MemberType NoteProperty -Name Patches -Value @(); }
        $ResolvedExisting = $Context.Patches | ForEach-Object { Resolve-Path -Path $_ -RelativeBasePath $PSScriptRoot; };
        $Patches = $Patches | ForEach-Object { Resolve-Path -Path $_ -RelativeBasePath $PSScriptRoot } | Where-Object { $ResolvedExisting -notcontains $_ }

        if (-not $Patches -or $Patches.Length -le 0) {
            return
        }

        Invoke-Info "Applying patches to $($OutputPath).";

        $Encoding = Get-ContentEncoding -Path $OutputPath;
        $Content = Get-Content -Path $OutputPath -Raw;
        $Content = $Content.Substring($Content.IndexOf("`n") + 1);
        Out-WithEncoding -Path $OutputPath -Content $Content -Encoding $Encoding;

        $applyResult = git apply --no-index --ignore-space-change $Patches 2>&1
        if ($LASTEXITCODE -ne 0) {
            Invoke-Error "Failed to apply patches: $applyResult"
            $ErrorRecord = New-Object System.Management.Automation.ErrorRecord `
            (New-Object System.Exception($applyResult), 'PatchApplicationFailed', `
                    [System.Management.Automation.ErrorCategory]::InvalidOperation, $Patches)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord);
        }
        $Context.Patches += $Patches;
        Out-WithContextAndEncoding `
            -Path $OutputPath `
            -Context $Context `
            -Content (Get-Content -Path $OutputPath -Raw) `
            -Encoding (Get-ContentEncoding -Path $OutputPath);
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

function New-ScriptPatch {
    [CmdletBinding()]
    [OutputType([Void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
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
    foreach ($RawDefinition in $Definitions) {
        $Definition = Get-Content -Path $RawDefinition.FullName | ConvertFrom-Json;
        $Script = Resolve-Path (Join-Path -Path $Output -ChildPath $Definition.Output);
        if (-not (Test-Path -Path $Script -PathType Leaf)) {
            Invoke-Warn "Output file $($Script) does not exist, skipping...";
            continue;
        }

        $Encoding = Get-ContentEncoding -Path $Script;
        $Content = Get-Content -Path $Script -Raw;
        $Content = $Content.Substring($Content.IndexOf("`n") + 1);
        Out-WithEncoding -Path $Script -Content $Content -Encoding $Encoding;
    }

    git add $Output

    $Continue = Get-UserConfirmation -Title 'Patch Creation' -Question 'Make your changes then press ''Yes'' to continue, or ''No'' to abort.' -Default $True;
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
            $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($OutputPath);
            while ($True) {
                $PatchName = Get-UserInput -Title 'Patch Name' -Question "Provide a name for the changes applied to $($Definition.Output).";
                $PatchName = Join-Path -Path $Patches -ChildPath ("${BaseName}_${PatchName}.patch");

                if (Test-Path -Path $PatchName -PathType Leaf) {
                    Invoke-Warn "Patch $($PatchName) already exists, please provide a different name.";
                    continue;
                } else {
                    break;
                }
            }

            git diff $OutputPath > $PatchName;

            $Definition.Patches += $PatchName;
            $Definition | ConvertTo-Json | Set-Content -Path $RawDefinition.FullName;

            git add $PatchName;
            git add $RawDefinition.FullName;
            Invoke-Info "Patch created at $PatchName.";

            git checkout HEAD -- $OutputPath;
            try {
                Invoke-ApplyPatch -OutputPath $OutputPath -Patches $Definition.Patches;
                git add $OutputPath;
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

function Get-Context {
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [String]$Path
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $Content = Get-Content -Path $Path -Raw;
        $Context = $Content -split "`n" | Select-Object -First 1;

        $Context = $Context.Substring(9); # Drop #!ignore
        return $Context | ConvertFrom-Json;
    }
}

function New-Context {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Hash,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$OutputPath,


        [Parameter()]
        [String[]]$Patches
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $Context = [PSCustomObject]@{
            Hash = $Hash;
            Patches = $Patches;
        }

        return $Context;
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
        New-ScriptPatch -Definitions $WantedDefinitions -Patches $Patches;
    }
};
