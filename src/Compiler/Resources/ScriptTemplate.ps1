#!ignore
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidGlobalVars',
    'Global:CompiledScript',
    Justification = 'Required to inform modules of runtime type.'
)]
<#!DEFINE PARAM_BLOCK >#> param()
begin {
    [Boolean]$Global:CompiledScript = $True;
    <#!DEFINE EMBEDDED_MODULES#>
    <#!DEFINE IMPORT_ORDER#>

    [String]$Local:PrivatePSModulePath = $env:ProgramData | Join-Path -ChildPath "AMT/PowerShell/Modules/PS$($PSVersionTable.PSVersion.Major)";
    if (-not (Test-Path -Path $Local:PrivatePSModulePath)) {
        Write-Verbose "Creating module root folder: $Local:PrivatePSModulePath";
        New-Item -Path $Local:PrivatePSModulePath -ItemType Directory -WhatIf:$False | Out-Null;
    }

    if (-not ($Env:PSModulePath -like "*$Local:PrivatePSModulePath*")) {
        $Env:PSModulePath = "$Local:PrivatePSModulePath;" + $Env:PSModulePath;
    }

    # Must use UTF-8 Bom for PS < 6 to properly handle Unicode characters.
    $Local:PSBelow6 = $PSVersionTable.PSVersion.Major -lt 6;
    $Local:Bom = [Byte[]](0xEF, 0xBB, 0xBF);
    $Local:Encoding = 'UTF8';

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
            New-Item -Path $Local:ModuleFolderPath -ItemType Directory -WhatIf:$False | Out-Null;
        }

        switch ($_.Type) {
            'UTF8String' {
                $Local:FileSuffix = if ($null -eq $Script:ScriptPath) { 'ps1' } else { 'psm1' };
                $Local:InnerModulePath = Join-Path -Path $Local:ModuleFolderPath -ChildPath "$Local:NameHash.$Local:FileSuffix";

                if (-not (Test-Path -Path $Local:InnerModulePath)) {
                    Write-Verbose "Writing content to module file: $Local:InnerModulePath"
                    Set-Content -Path $Local:InnerModulePath -Value $Content -Encoding $Local:Encoding -WhatIf:$False;
                } else {
                    $Local:Params = @{ Path = $Local:InnerModulePath; TotalCount = $Local:Bom.Length; };
                    if ($Local:PSBelow6) { $Local:Params.Add('Encoding', 'Byte'); } else { $Local:Params.Add('AsByteStream', $True); }

                    $Local:WantBom = $Local:PSBelow6
                    $Local:IsBomEncoded = [Collections.Generic.SortedSet[String]]::CreateSetComparer().Equals((Get-Content @Local:Params), $Local:Bom);

                    if ($Local:WantBom -ne $Local:IsBomEncoded) {
                        Write-Debug "Replacing module to ensure correct UTF-8 encoding: $Local:InnerModulePath"

                        Set-Content -Path $Local:InnerModulePath -Value $Content -Encoding $Local:Encoding -Force -WhatIf:$False;
                    }
                }

                if ($null -eq $Script:ScriptPath) {
                    $Script:ScriptPath = $Local:InnerModulePath;
                }
            }
            'Zip' {
                if ((Get-ChildItem -Path $Local:ModuleFolderPath).Count -ne 0) {
                    return;
                }
                [String]$Local:TempFile = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.zip');
                [Byte[]]$Local:Bytes = [System.Convert]::FromBase64String($Content);
                [System.IO.File]::WriteAllBytes($Local:TempFile, $Local:Bytes);

                Write-Verbose "Expanding module file: $Local:TempFile"
                Expand-Archive -Path $Local:TempFile -DestinationPath $Local:ModuleFolderPath -Force -WhatIf:$False;
            }
            Default {
                Write-Warning "Unknown module type: $($_)";
            }
        }
    }
}
process {
    try {
        function ConvertTo-InvokableValue {
            [CmdletBinding()]
            [OutputType([String])]
            param(
                [Parameter(Mandatory)]
                [AllowNull()]
                [Object]$Value
            )

            process {
                if ($null -eq $Value) { return '$null' };

                $Type = $Value.GetType();

                if ($Type -eq [Boolean]) {
                    return "`$$Value";
                } elseif ($Type -eq [Object[]]) {
                    $Array = @();
                    foreach ($Element in $Value) {
                        $Array += ConvertTo-InvokableValue -Value $Element;
                    }

                    return '@(' + ($Array -join ', ') + ')';
                } elseif ($Type -eq [Hashtable]) {
                    $Hashtable = @();
                    foreach ($Key in $Value.Keys) {
                        $Hashtable += "$Key = $(ConvertTo-InvokableValue -Value $Value[$Key])";
                    }

                    return '@{' + ($Hashtable -join '; ') + '}';
                } elseif ($Type -eq [PSCustomObject]) {
                    $Hashtable = @();
                    foreach ($Property in $Value.PSObject.Properties) {
                        $Hashtable += "$($Property.Name)=$(ConvertTo-InvokableValue -Value $Property.Value)";
                    }

                    return '[PSCustomObject]@{' + ($Hashtable -join '; ') + '}';
                }

                return ConvertTo-Json -InputObject $Value;
            }
        }

        if ($env:COMPILED_NO_JOB -ne $True) {
            $PowerShellPath = Get-Process -Id $PID | Select-Object -ExpandProperty Path;

            # Fucking PS5 is dumb
            $ArgSplat = @{ }
            $PSBoundParameters.GetEnumerator() | ForEach-Object {
                $Value;
                if ($_.Value -is [System.Management.Automation.SwitchParameter]) {
                    $Value = $_.Value.ToBool();
                } else {
                    $Value = $_.Value;
                }
                $InvokableValue = ConvertTo-InvokableValue -Value $Value;

                if ($ArgSplat.ContainsKey($_.Key)) {
                    $ArgSplat[$_.Key] = $InvokableValue;
                } else {
                    $ArgSplat.Add($_.Key, $InvokableValue);
                }
            }

            & "$PowerShellPath" -NoProfile -Command $Script:ScriptPath @ArgSplat
        } else {
            & $Script:ScriptPath @PSBoundParameters;
        }
    } finally {
        $Env:PSModulePath = ($Env:PSModulePath -split ';' | Select-Object -Skip 1) -join ';';
        $Script:REMOVE_ORDER | ForEach-Object { Get-Module -Name $_ | Remove-Module -Force -WhatIf:$False; }
    }
} end {
    Remove-Variable -Name CompiledScript -Scope Global -WhatIf:$False;
}
