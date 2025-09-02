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
                } elseif ($Type.IsArray) {
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
                } elseif ($Type.FullName -like 'System.Tuple``*') {
                    $Elements = @();
                    for ($i = 0; $i -lt $Value.GetType().GenericTypeArguments.Count; $i++) {
                        $Elements += ConvertTo-InvokableValue -Value $Value[$i];
                    }
                    return '[Tuple]::Create(' + ($Elements -join ', ') + ')';
                } elseif ($Type.IsSerializable -and -not $Type.IsPrimitive) {
                    # For PowerShell versions without native inline ConvertTo-CliXml support,
                    # export the argument to a temporary CLIXML file and import it at runtime.
                    if ($PSVersionTable.PSVersion -lt [Version]'7.5') {
                        $argFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ('arg_' + ([System.Guid]::NewGuid().ToString()) + '.clixml'))
                        $Value | Export-Clixml -Path $argFile -Depth 5
                        return "(Import-Clixml -Path '$argFile')";
                    } else {
                        return "(ConvertFrom-CliXML -InputObject '$(($Value | ConvertTo-CliXml -Depth 5) -replace "'", "''")')";
                    }
                }

                return ConvertTo-Json -InputObject $Value;
            }
        }

        function Invoke-ScriptWithErrorCapture {
            <#
            .SYNOPSIS
                Runs a PowerShell script while capturing errors as rich objects.

            .DESCRIPTION
                Executes a PowerShell script in a new process,
                maintaining interactivity (this is why we can't just do a $result = )
                while capturing any errors that occur using file-based serialization.

            .PARAMETER ScriptPath
                The path to the PowerShell script to execute.

            .PARAMETER ArgumentTable
                A HashTable of arguments to pass to the script.

            .NOTES
                Errors captured will be limited in their depth to 5 levels.
            #>
            [CmdletBinding()]
            [OutputType([System.Management.Automation.ErrorRecord[]])]
            param(
                [Parameter(Mandatory = $true, Position = 0)]
                [string]$ScriptPath,

                [Parameter(Position = 1)]
                [HashTable]$ArgumentTable
            )

            if (-not (Test-Path -Path $ScriptPath -PathType Leaf)) {
                throw "Script not found at path: $ScriptPath"
            }

            $PowerShellPath = Get-Process -Id $PID | Select-Object -ExpandProperty Path;

            if ($env:NO_ERROR_WRAPPER -eq $True) {
                Write-Verbose 'Skipping error capture wrapper due to NO_ERROR_WRAPPER environment variable.';
                & "$PowerShellPath" -NoProfile -File "$ScriptPath" @PSBoundParameters;
                return;
            }

            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) 'PSErrorCapture'
            New-Item -Path $tempDir -ItemType Directory -Force -WhatIf:$False | Out-Null
            $ErrorOutputPath = Join-Path $tempDir "script_$PID_$(Get-Random)_errors.xml"

            try {
                $wrapperPath = Join-Path ([System.IO.Path]::GetTempPath()) "error_wrapper_$(Get-Random).ps1"
                @"
`$Error.Clear()

`$Script:DisplayedErrorLog = [System.Collections.Generic.List[pscustomobject]]::new()
`$Script:__ErrorComingFromStream = `$False

`$ArgSplat = $(ConvertTo-InvokableValue $ArgumentTable)
try {
    & "$ScriptPath" @ArgSplat 2>&1 | ForEach-Object {
        if (`$_ -is [System.Management.Automation.ErrorRecord]) {
            if (`$_.ErrorDetails.RecommendedAction -ne 'Silent') {
                Write-Error -ErrorRecord `$_ -ErrorAction Continue
            }

            `$Script:DisplayedErrorLog.Add(`$_)
        }
    }
} finally {
    if (`$Script:DisplayedErrorLog.Count -gt 0) {
        `$Script:DisplayedErrorLog | Export-Clixml -Path "$ErrorOutputPath" -Depth 4
    } else {
        Set-Content -Path "$ErrorOutputPath" -Value "NO_ERRORS" -Force
    }
}
"@ | Set-Content -Path $wrapperPath -Encoding UTF8 -WhatIf:$False


                & "$PowerShellPath" -NoProfile -File "$wrapperPath"

                $capturedErrors = @()
                if (Test-Path -Path $ErrorOutputPath) {
                    $fileContent = Get-Content -Path $ErrorOutputPath -Raw -ErrorAction SilentlyContinue
                    if ($fileContent.Trim() -ne 'NO_ERRORS') {
                        $capturedErrors = Import-Clixml -Path $ErrorOutputPath

                        Write-Debug "Captured $($capturedErrors.Count) errors from script execution:"
                        foreach ($err in $capturedErrors) {
                            if ($err.ErrorCategory_Reason -eq 'ParentContainsErrorRecordException') {
                                continue;
                            }

                            $Global:Error.Insert(0, $err)
                        }
                    } else {
                        Write-Debug 'No errors were captured during script execution'
                    }
                } else {
                    Write-Warning 'Error output file was not created. Script may have terminated unexpectedly.'
                }

                if ($DebugPreference -eq 'Continue') {
                    return $capturedErrors
                }
            } finally {
                # Always clean arguments
                $argPattern = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'arg_*.clixml')
                Get-ChildItem -Path $argPattern -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

                if ($DebugPreference -ne 'Continue') {
                    if (Test-Path $wrapperPath) {
                        Remove-Item -Path $wrapperPath -Force -ErrorAction SilentlyContinue -WhatIf:$False
                    }

                    if (Test-Path $ErrorOutputPath) {
                        Remove-Item -Path $ErrorOutputPath -Force -ErrorAction SilentlyContinue -WhatIf:$False
                    }
                }
            }
        }

        if ($env:COMPILED_NO_RUN -eq $True) {
            Write-Verbose 'Skipping script execution due to COMPILED_NO_RUN environment variable.';
            return;
        }

        if ($env:COMPILED_NO_JOB -ne $True) {
            $ArgSplat = @{ }
            $PSBoundParameters.GetEnumerator() | ForEach-Object {
                $Value;
                if ($_.Value -is [System.Management.Automation.SwitchParameter]) {
                    $Value = $_.Value.ToBool();
                } else {
                    $Value = $_.Value;
                }

                if ($ArgSplat.ContainsKey($_.Key)) {
                    $ArgSplat[$_.Key] = $Value;
                } else {
                    $ArgSplat.Add($_.Key, $Value);
                }
            } | Out-Null;

            Invoke-ScriptWithErrorCapture $Script:ScriptPath $ArgSplat
        } else {
            & $Script:ScriptPath @PSBoundParameters;
        }
    } finally {
        $Env:PSModulePath = ($Env:PSModulePath -split ';' | Select-Object -Skip 1) -join ';';
        $Script:REMOVE_ORDER | ForEach-Object { Get-Module -Name $_ | Remove-Module -Force -WhatIf:$False; }
    }
} end {
    Remove-Variable -Name CompiledScript -Scope Global -WhatIf:$False -ErrorAction SilentlyContinue;
}
