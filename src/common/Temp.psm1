function Get-NamedTempFolder {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,

        [switch]$ForceEmpty
    )

    [String]$Local:Folder = [System.IO.Path]::GetTempPath() | Join-Path -ChildPath $Name;
    if ($ForceEmpty -and (Test-Path $Local:Folder -PathType Container)) {
        Write-Verbose -Message "Emptying temporary folder $Local:Folder...";
        Remove-Item -Path $Local:Folder -Force -Recurse;
    }

    if (-not (Test-Path $Local:Folder -PathType Container)) {
        Write-Verbose -Message "Creating temporary folder $Local:Folder...";
        New-Item -ItemType Directory -Path $Local:Folder;
    } elseif (Test-Path $Local:Folder -PathType Container) {
        Write-Verbose -Message "Temporary folder $Local:Folder already exists.";
        if ($ForceEmpty) {
            Write-Verbose -Message "Emptying temporary folder $Local:Folder...";
            Remove-Item -Path $Local:Folder -Force -Recurse;
        }
    }

    return $Local:Folder;
}

function Get-UniqueTempFolder {
    return Get-NamedTempFolder -Name ([System.IO.Path]::GetRandomFileName()) -ForceEmpty;
}

function Invoke-WithinEphemeral {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$ScriptBlock
    )

    [String]$Local:Folder = Get-UniqueTempFolder;
    try {
        Write-Verbose -Message "Executing script block within temporary folder $Local:Folder...";
        Push-Location -Path $Local:Folder;
        & $ScriptBlock;
    } finally {
        Write-Verbose -Message "Cleaning temporary folder $Local:Folder...";
        Pop-Location;
        Remove-Item -Path $Local:Folder -Force -Recurse;
    }
}

Export-ModuleMember -Function Get-NamedTempFolder, Get-UniqueTempFolder, Invoke-WithinEphemeral;
