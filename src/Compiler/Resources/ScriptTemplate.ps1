begin {
    $Global:CompiledScript = $True;
    #!DEFINE EMBEDDED_MODULES

    $Local:PrivatePSModulePath = $env:ProgramData | Join-Path -ChildPath 'AMT/PowerShell/Modules';
    if (-not (Test-Path -Path $Local:PrivatePSModulePath)) {
        Write-Host "Creating module root folder: $Local:PrivatePSModulePath";
        New-Item -Path $Local:PrivatePSModulePath -ItemType Directory | Out-Null;
    }
    if (-not ($Env:PSModulePath -like "*$Local:PrivatePSModulePath*")) {
        $Env:PSModulePath = "$Local:PrivatePSModulePath;" + $Env:PSModulePath;
    }
    $Script:EMBEDDED_MODULES.GetEnumerator() | ForEach-Object {
        $Local:Content = $_.Value.Content;
        $Local:Name = $_.Key;
        $Local:ModuleFolderPath = Join-Path -Path $Local:PrivatePSModulePath -ChildPath $Local:Name;
        if (-not (Test-Path -Path $Local:ModuleFolderPath)) {
            Write-Host "Creating module folder: $Local:ModuleFolderPath";
            New-Item -Path $Local:ModuleFolderPath -ItemType Directory | Out-Null;
        }
        switch ($_.Value.Type) {
            'UTF8String' {
                $Local:InnerModulePath = Join-Path -Path $Local:ModuleFolderPath -ChildPath "$Local:Name.psm1";
                if (-not (Test-Path -Path $Local:InnerModulePath)) {
                    Write-Host "Writing content to module file: $Local:InnerModulePath"
                    Set-Content -Path $Local:InnerModulePath -Value $Content;
                }
            }
            'ZipHex' {
                if ((Get-ChildItem -Path $Local:ModuleFolderPath).Count -ne 0) {
                    return;
                }
                [String]$Local:TempFile = [System.IO.Path]::GetTempFileName();
                [Byte[]]$Local:Bytes = [System.Convert]::FromHexString($Content);
                [System.IO.File]::WriteAllBytes($Local:TempFile, $Local:Bytes);
                Write-Host "Expanding module file: $Local:TempFile"
                Expand-Archive -Path $Local:TempFile -DestinationPath $Local:ModuleFolderPath -Force;
            }
            Default {
                Write-Warning "Unknown module type: $($_)";
            }
        }
    }
}
process {
    $Private:ScriptContents = $Script:EMBEDDED_MODULES[0];
    Invoke-Expression -Command $Private:ScriptContents;
}
end {
    $Env:PSModulePath = ($Env:PSModulePath -split ';' | Select-Object -Skip 1) -join ';';
    Remove-Variable -Scope Global -Name CompiledScript, EMBEDDED_MODULES;
}
