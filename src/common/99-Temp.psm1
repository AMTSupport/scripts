function Get-NamedTempFolder {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,

        [switch]$ForceEmpty
    )

    [String]$Local:Folder = [System.IO.Path]::GetTempPath() | Join-Path -ChildPath $Name;
    if ($ForceEmpty -and (Test-Path $Local:Folder -PathType Container)) {
        Invoke-Verbose -Message "Emptying temporary folder $Local:Folder...";
        Remove-Item -Path $Local:Folder -Force -Recurse | Out-Null;
    }

    if (-not (Test-Path $Local:Folder -PathType Container)) {
        Invoke-Verbose -Message "Creating temporary folder $Local:Folder...";
        New-Item -ItemType Directory -Path $Local:Folder | Out-Null;
    } elseif (Test-Path $Local:Folder -PathType Container) {
        Invoke-Verbose -Message "Temporary folder $Local:Folder already exists.";
        if ($ForceEmpty) {
            Invoke-Verbose -Message "Emptying temporary folder $Local:Folder...";
            Remove-Item -Path $Local:Folder -Force -Recurse | Out-Null;
        }
    }

    return $Local:Folder;
}

function Get-UniqueTempFolder {
    Get-NamedTempFolder -Name ([System.IO.Path]::GetRandomFileName()) -ForceEmpty;
}

function Invoke-WithinEphemeral {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$ScriptBlock
    )

    [String]$Local:Folder = Get-UniqueTempFolder;
    try {
        Invoke-Verbose -Message "Executing script block within temporary folder $Local:Folder...";
        Push-Location -Path $Local:Folder;
        & $ScriptBlock;
    } finally {
        Invoke-Verbose -Message "Cleaning temporary folder $Local:Folder...";
        Pop-Location;
        Remove-Item -Path $Local:Folder -Force -Recurse;
    }
}

Export-ModuleMember -Function Get-NamedTempFolder, Get-UniqueTempFolder, Invoke-WithinEphemeral;
