#!DEFINE PARAM_BLOCK
begin {
    [Boolean]$Script:CompiledScript = $True;
    #!DEFINE EMBEDDED_MODULES
    #!DEFINE IMPORT_ORDER

    [String]$Local:PrivatePSModulePath = $env:ProgramData | Join-Path -ChildPath 'AMT/PowerShell/Modules';
    if (-not (Test-Path -Path $Local:PrivatePSModulePath)) {
        Write-Verbose "Creating module root folder: $Local:PrivatePSModulePath";
        New-Item -Path $Local:PrivatePSModulePath -ItemType Directory | Out-Null;
    }

    if (-not ($Env:PSModulePath -like "*$Local:PrivatePSModulePath*")) {
        $Env:PSModulePath = "$Local:PrivatePSModulePath;" + $Env:PSModulePath;
    }

    $Script:ScriptPath;
    $Script:EMBEDDED_MODULES | ForEach-Object {
        $Local:Name = $_.Name;
        $Local:Type = $_.Type;
        $Local:Hash = $_.Hash;
        $Local:Content = $_.Content;
        $Local:NameHash = "$Local:Name-$Local:Hash";
        if (-not $Local:Name -or -not $Local:Type -or -not $Local:Hash -or -not $Local:Content) {
            Write-Warning "Invalid module definition: $($_), skipping...";
            return;
        }

        $Local:ModuleFolderPath = Join-Path -Path $Local:PrivatePSModulePath -ChildPath $Local:NameHash;
        if (-not (Test-Path -Path $Local:ModuleFolderPath)) {
            Write-Verbose "Creating module folder: $Local:ModuleFolderPath";
            New-Item -Path $Local:ModuleFolderPath -ItemType Directory | Out-Null;
        }

        switch ($_.Type) {
            'UTF8String' {
                $Local:FileSuffix = if ($null -eq $Script:ScriptPath) { 'ps1' } else { 'psm1' };
                $Local:InnerModulePath = Join-Path -Path $Local:ModuleFolderPath -ChildPath "$Local:NameHash.$Local:FileSuffix";
                if (-not (Test-Path -Path $Local:InnerModulePath)) {
                    Write-Verbose "Writing content to module file: $Local:InnerModulePath"
                    Set-Content -Path $Local:InnerModulePath -Value $Content;
                }
                if ($null -eq $Script:ScriptPath) {
                    $Script:ScriptPath = $Local:InnerModulePath;
                }
            }
            'Zip' {
                if ((Get-ChildItem -Path $Local:ModuleFolderPath).Count -ne 0) {
                    return;
                }
                [String]$Local:TempFile = [System.IO.Path]::GetTempFileName();
                [Byte[]]$Local:Bytes = [System.Convert]::FromBase64String($Content);
                [System.IO.File]::WriteAllBytes($Local:TempFile, $Local:Bytes);

                Write-Verbose "Expanding module file: $Local:TempFile"
                Expand-Archive -Path $Local:TempFile -DestinationPath $Local:ModuleFolderPath -Force;

                $Local:ManifestPath = Join-Path -Path $Local:ModuleFolderPath -ChildPath "$Local:Name.psd1";
                $Local:NewManifestPath = Join-Path -Path $Local:ModuleFolderPath -ChildPath "$Local:NameHash.psd1";
                Move-Item -Path $Local:ManifestPath -Destination $Local:NewManifestPath -Force;
            }
            Default {
                Write-Warning "Unknown module type: $($_)";
            }
        }
    }
}
process {
    try {
        & $Script:ScriptPath @PSBoundParameters;
    } finally {
        $Env:PSModulePath = ($Env:PSModulePath -split ';' | Select-Object -Skip 1) -join ';';
        $Script:REMOVE_ORDER | ForEach-Object { Get-Module -Name $_ | Remove-Module -Force; }
    }
}
