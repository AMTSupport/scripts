#!ignore
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidGlobalVars',
    'Global:CompiledScript',
    Justification = 'Required to inform modules of runtime type.'
)]
<#!DEFINE PARAM_BLOCK >#> param()
begin {
    try {
        [Boolean]$Global:CompiledScript = $True;
    <#!DEFINE RUNTIME_MODULE#>
    <#!DEFINE RUNTIME_MODULE_NAME#>
    <#!DEFINE EMBEDDED_MODULES#>
    <#!DEFINE IMPORT_ORDER#>

    if ($env:ProgramData) {
        $Local:ProgramData = $env:ProgramData;
    } elseif ([Environment]::GetFolderPath('CommonApplicationData')) {
        $Local:ProgramData = [Environment]::GetFolderPath('CommonApplicationData');
    } else {
        $Local:ProgramData = Join-Path $HOME '.local/share';
    }

    [String]$Local:PrivatePSModulePath = $Local:ProgramData | Join-Path -ChildPath "AMT/PowerShell/Modules/PS$($PSVersionTable.PSVersion.Major)";
    if (-not (Test-Path -Path $Local:PrivatePSModulePath)) {
        Write-Verbose "Creating module root folder: $Local:PrivatePSModulePath";
        New-Item -Path $Local:PrivatePSModulePath -ItemType Directory -Force -WhatIf:$False | Out-Null;
    }

    $Script:OriginalPSModulePath = $Env:PSModulePath;
    $Local:PSModulePathSeparator = [System.IO.Path]::PathSeparator;
    if (-not ($Env:PSModulePath -like "*$Local:PrivatePSModulePath*")) {
        $Env:PSModulePath = "$Local:PrivatePSModulePath$Local:PSModulePathSeparator" + $Env:PSModulePath;
    }

    [Int]$Script:ModuleLockTimeoutSeconds = 180;
    [Int]$Script:ModuleLockRetryMilliseconds = 200;

    function Test-ZipModuleReady {
        [CmdletBinding()]
        [OutputType([Boolean])]
        param(
            [Parameter(Mandatory)]
            [String]$ReadyPath,

            [Parameter(Mandatory)]
            [String]$ModuleFolderPath
        )

        if (-not (Test-Path -Path $ReadyPath -PathType Leaf)) {
            return $false;
        }

        $Local:ModuleFiles = Get-ChildItem -Path $ModuleFolderPath -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.ready' };
        return $null -ne $Local:ModuleFiles -and $Local:ModuleFiles.Count -gt 0;
    }

    function Wait-ModuleLock {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [String]$LockPath,

            [Parameter(Mandatory)]
            [String]$ModuleName,

            [Parameter(Mandatory)]
            [String]$ModuleHash,

            [String]$ReadyPath,

            [String]$ModuleFolderPath,

            [Nullable[Int]]$TimeoutSeconds = $null,

            [Nullable[Int]]$RetryMilliseconds = $null
        )

        if ($null -eq $TimeoutSeconds -or $TimeoutSeconds.Value -le 0) {
            $TimeoutSeconds = $Script:ModuleLockTimeoutSeconds;
        }

        if ($null -eq $RetryMilliseconds -or $RetryMilliseconds.Value -le 0) {
            $RetryMilliseconds = $Script:ModuleLockRetryMilliseconds;
        }

        $Local:Stopwatch = [System.Diagnostics.Stopwatch]::StartNew();
        $Local:LockDirectory = Split-Path -Path $LockPath -Parent;
        if (-not (Test-Path -Path $Local:LockDirectory)) {
            New-Item -Path $Local:LockDirectory -ItemType Directory -Force -WhatIf:$False | Out-Null;
        }

        while ($true) {
            try {
                $Local:LockHandle = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None);
                $Local:LockHandle.SetLength(0);
                $Local:LockBytes = [System.Text.Encoding]::UTF8.GetBytes("PID=$PID`nModule=$ModuleName`nHash=$ModuleHash`nStarted=$([DateTime]::UtcNow.ToString('o'))");
                $Local:LockHandle.Write($Local:LockBytes, 0, $Local:LockBytes.Length);
                $Local:LockHandle.Flush();
                return $Local:LockHandle;
            } catch [System.IO.IOException] {
                if (Test-ZipModuleReady -ReadyPath $ReadyPath -ModuleFolderPath $ModuleFolderPath) {
                    return $null;
                }

                if ($Local:Stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                    throw "Timed out waiting for module lock '$LockPath' for module '$ModuleName' ($ModuleHash)."
                }

                Start-Sleep -Milliseconds $RetryMilliseconds;
            }
        }
    }

    function Complete-ModuleLock {
        [CmdletBinding()]
        param(
            [AllowNull()]
            [System.IDisposable]$LockHandle,

            [Parameter(Mandatory)]
            [String]$LockPath,

            [String]$ReadyPath,

            [String]$ModuleFolderPath,

            [Boolean]$OperationSucceeded = $false
        )

        try {
            $Local:OwnerSucceeded = $OperationSucceeded;

            if ($Local:OwnerSucceeded -and $ReadyPath -and $ModuleFolderPath -and -not (Test-Path -Path $ReadyPath -PathType Leaf)) {
                $Local:ModuleFiles = Get-ChildItem -Path $ModuleFolderPath -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.ready' };
                if ($null -ne $Local:ModuleFiles -and $Local:ModuleFiles.Count -gt 0) {
                    Set-Content -Path $ReadyPath -Value ([DateTime]::UtcNow.ToString('o')) -Encoding UTF8 -Force -WhatIf:$False;
                }
            }

            # Capture ownership before dispose so owner can clean up lock in finally
            $owned = $null -ne $LockHandle;
            if ($null -ne $LockHandle) {
                $LockHandle.Dispose();
                $LockHandle = $null;
            }
        } finally {
            if ($null -ne $LockHandle) {
                $LockHandle.Dispose();
            }

            if ($owned -and (Test-Path -Path $LockPath -PathType Leaf)) {
                Remove-Item -Path $LockPath -Force -ErrorAction SilentlyContinue -WhatIf:$False;
            }
        }
    }

    if (-not $RUNTIME_MODULE -or -not $RUNTIME_MODULE_NAME) {
        throw 'Missing runtime module definition in compiled template.';
    }

    $Local:RuntimeModuleName = $RUNTIME_MODULE_NAME;
    $Local:RuntimeModuleHash = $RUNTIME_MODULE.Hash;
    $Local:RuntimeModuleType = $RUNTIME_MODULE.Type;
    $Local:RuntimeModuleContent = $RUNTIME_MODULE.Content;

    if (-not $Local:RuntimeModuleName -or -not $Local:RuntimeModuleHash -or -not $Local:RuntimeModuleType -or -not $Local:RuntimeModuleContent) {
        throw 'Invalid runtime module definition in compiled template.';
    }

    if ($Local:RuntimeModuleType -ne 'Zip') {
        throw "Unsupported runtime module type '$Local:RuntimeModuleType'.";
    }

    $Local:RuntimeModuleFolderPath = Join-Path -Path $Local:PrivatePSModulePath -ChildPath "$Local:RuntimeModuleName-$Local:RuntimeModuleHash";
    if (-not (Test-Path -Path $Local:RuntimeModuleFolderPath)) {
        Write-Verbose "Creating runtime module folder: $Local:RuntimeModuleFolderPath";
        New-Item -Path $Local:RuntimeModuleFolderPath -ItemType Directory -Force -WhatIf:$False | Out-Null;
    }

    $Local:RuntimeModuleLockPath = Join-Path -Path $Local:PrivatePSModulePath -ChildPath "$Local:RuntimeModuleName-$Local:RuntimeModuleHash.lock";
    $Local:RuntimeModuleReadyPath = Join-Path -Path $Local:RuntimeModuleFolderPath -ChildPath '.ready';
    $Local:RuntimeManifestPath = Join-Path -Path $Local:RuntimeModuleFolderPath -ChildPath "$Local:RuntimeModuleName.psd1";

    if (-not (Test-ZipModuleReady -ReadyPath $Local:RuntimeModuleReadyPath -ModuleFolderPath $Local:RuntimeModuleFolderPath)) {
        $Local:RuntimeLockHandle = Wait-ModuleLock -LockPath $Local:RuntimeModuleLockPath -ModuleName $Local:RuntimeModuleName -ModuleHash $Local:RuntimeModuleHash -ReadyPath $Local:RuntimeModuleReadyPath -ModuleFolderPath $Local:RuntimeModuleFolderPath;
        [String]$Local:RuntimeTempFile = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.zip');
        [Boolean]$Local:RuntimeSucceeded = $false;
        try {
            if (-not (Test-ZipModuleReady -ReadyPath $Local:RuntimeModuleReadyPath -ModuleFolderPath $Local:RuntimeModuleFolderPath)) {
                Write-Verbose "Preparing runtime module folder: $Local:RuntimeModuleFolderPath";
                Get-ChildItem -Path $Local:RuntimeModuleFolderPath -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.ready' } | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue -WhatIf:$False;

                [Byte[]]$Local:RuntimeBytes = [System.Convert]::FromBase64String($Local:RuntimeModuleContent);
                [System.IO.File]::WriteAllBytes($Local:RuntimeTempFile, $Local:RuntimeBytes);

                Write-Verbose "Expanding runtime module file: $Local:RuntimeTempFile to $Local:RuntimeModuleFolderPath";
                try {
                    Expand-Archive -Path $Local:RuntimeTempFile -DestinationPath $Local:RuntimeModuleFolderPath -Force -WhatIf:$False -ErrorAction Stop;
                    $Local:RuntimeSucceeded = $true;
                    Write-Verbose "Expanded runtime module file successfully: $Local:RuntimeTempFile";
                } catch {
                    throw "Failed to expand runtime module archive '$Local:RuntimeTempFile' to '$Local:RuntimeModuleFolderPath': $($_.Exception.Message)";
                }
            } else {
                $Local:RuntimeSucceeded = $true;
            }
        } finally {
            if (Test-Path -Path $Local:RuntimeTempFile) {
                Remove-Item -Path $Local:RuntimeTempFile -Force -ErrorAction SilentlyContinue -WhatIf:$False;
            }

            Complete-ModuleLock -LockHandle $Local:RuntimeLockHandle -LockPath $Local:RuntimeModuleLockPath -ReadyPath $Local:RuntimeModuleReadyPath -ModuleFolderPath $Local:RuntimeModuleFolderPath -OperationSucceeded $Local:RuntimeSucceeded;
        }
    }

    try {
        Import-Module -Name $Local:RuntimeManifestPath -Force -ErrorAction Stop;
        $Local:RuntimeImportedModule = Get-Module -Name $Local:RuntimeModuleName -ErrorAction Stop;
    } catch {
        throw "Failed to import runtime module '$Local:RuntimeModuleName' from '$Local:RuntimeManifestPath': $($_.Exception.Message)";
    }

    if (-not (Get-Command -Name 'Initialize-AMTCompiledRuntime' -Module $Local:RuntimeModuleName -ErrorAction SilentlyContinue)) {
        throw "Runtime module '$Local:RuntimeModuleName' does not expose cmdlet 'Initialize-AMTCompiledRuntime'.";
    }

    try {
        $Local:RuntimeState = Initialize-AMTCompiledRuntime -EmbeddedModules $Script:EMBEDDED_MODULES -PrivateModuleRoot $Local:PrivatePSModulePath;
    } catch {
        throw "Failed to initialize compiled runtime: $($_.Exception.Message)";
    }

    if ($null -ne $Local:RuntimeState) {
        if ($Local:RuntimeState.PSObject.Properties.Name -contains 'OriginalPSModulePath') { $Script:OriginalPSModulePath = $Local:RuntimeState.OriginalPSModulePath; }
        if ($Local:RuntimeState.PSObject.Properties.Name -contains 'ScriptPath') { $Script:ScriptPath = $Local:RuntimeState.ScriptPath; }
        if ($Local:RuntimeState.PSObject.Properties.Name -contains 'TransientScriptPath') { $Script:TransientScriptPath = $Local:RuntimeState.TransientScriptPath; }
        if ($Local:RuntimeState.PSObject.Properties.Name -contains 'PrivatePSModulePath') { $Local:PrivatePSModulePath = $Local:RuntimeState.PrivatePSModulePath; }
        if ($Local:RuntimeState.PSObject.Properties.Name -contains 'RuntimeModulePath') { $Local:RuntimeModulePath = $Local:RuntimeState.RuntimeModulePath; }
        if ($Local:RuntimeState.PSObject.Properties.Name -contains 'RuntimeModuleFolderPath') { $Local:RuntimeModuleFolderPath = $Local:RuntimeState.RuntimeModuleFolderPath; }
    }
} finally {
    if ($null -ne $Local:RuntimeImportedModule) {
        Remove-Module -ModuleInfo $Local:RuntimeImportedModule -Force -ErrorAction SilentlyContinue;
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
                        $Value | Export-Clixml -Path $argFile -Depth 5 -WhatIf:$false
                        return "(Import-Clixml -Path '$argFile')";
                    } else {
                        return "(ConvertFrom-CliXML -InputObject '$(($Value | ConvertTo-CliXml -Depth 5) -replace "'", "''")')";
                    }
                }

                return ConvertTo-Json -InputObject $Value;
            }
        }

        function Get-CompiledPowerShellPath {
            [CmdletBinding()]
            [OutputType([String])]
            param()

            $Local:Candidates = @();
            $Local:Seen = [System.Collections.Generic.HashSet[String]]::new([System.StringComparer]::OrdinalIgnoreCase);

            if (-not [String]::IsNullOrWhiteSpace($env:COMPILED_POWERSHELL_PATH)) {
                $Local:FullPath = $env:COMPILED_POWERSHELL_PATH;
                if (-not [System.IO.Path]::IsPathRooted($Local:FullPath)) {
                    try {
                        $Local:FullPath = [System.IO.Path]::GetFullPath($Local:FullPath);
                    } catch {
                        $Local:FullPath = $env:COMPILED_POWERSHELL_PATH;
                    }
                }

                if ($Local:Seen.Add($Local:FullPath)) {
                    $Local:Candidates += $Local:FullPath;
                }
            }

            if ($PSVersionTable.PSEdition -eq 'Core') {
                $Local:PowerShellExe = if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' };
                $Local:Candidate = Join-Path -Path $PSHOME -ChildPath $Local:PowerShellExe;
                if ($Local:Seen.Add($Local:Candidate)) {
                    $Local:Candidates += $Local:Candidate;
                }

                $Local:Candidate = Get-Command -Name pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source;
                if (-not [String]::IsNullOrWhiteSpace($Local:Candidate)) {
                    if (-not [System.IO.Path]::IsPathRooted($Local:Candidate)) {
                        try {
                            $Local:Candidate = [System.IO.Path]::GetFullPath($Local:Candidate);
                        } catch {
                        }
                    }

                    if ($Local:Seen.Add($Local:Candidate)) {
                        $Local:Candidates += $Local:Candidate;
                    }
                }
            } else {
                $Local:Candidate = Join-Path -Path $PSHOME -ChildPath 'powershell.exe';
                if ($Local:Seen.Add($Local:Candidate)) {
                    $Local:Candidates += $Local:Candidate;
                }

                $Local:Candidate = Get-Command -Name powershell -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source;
                if (-not [String]::IsNullOrWhiteSpace($Local:Candidate)) {
                    if (-not [System.IO.Path]::IsPathRooted($Local:Candidate)) {
                        try {
                            $Local:Candidate = [System.IO.Path]::GetFullPath($Local:Candidate);
                        } catch {
                        }
                    }

                    if ($Local:Seen.Add($Local:Candidate)) {
                        $Local:Candidates += $Local:Candidate;
                    }
                }
            }

            $Local:Candidate = Get-Process -Id $PID | Select-Object -ExpandProperty Path -ErrorAction SilentlyContinue;
            if (-not [String]::IsNullOrWhiteSpace($Local:Candidate)) {
                if (-not [System.IO.Path]::IsPathRooted($Local:Candidate)) {
                    try {
                        $Local:Candidate = [System.IO.Path]::GetFullPath($Local:Candidate);
                    } catch {
                    }
                }

                if ($Local:Seen.Add($Local:Candidate)) {
                    $Local:Candidates += $Local:Candidate;
                }
            }

            foreach ($Candidate in $Local:Candidates) {
                if (Test-Path -Path $Candidate -PathType Leaf) {
                    return $Candidate;
                }
            }

            throw "Unable to resolve PowerShell executable path. Set COMPILED_POWERSHELL_PATH to full path for powershell.exe or pwsh. PSHOME='$PSHOME', PSEdition='$($PSVersionTable.PSEdition)', PID='$PID'."
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

            $PowerShellPath = Get-CompiledPowerShellPath;

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

`$ArgSplat = $(ConvertTo-InvokableValue $ArgumentTable)
try {
    & "$ScriptPath" @ArgSplat 2>&1 6>&1 | ForEach-Object {
        if (`$_ -is [System.Management.Automation.ErrorRecord]) {
            # Skip PSReadLine module-init noise in non-interactive contexts
            if (`$_.InvocationInfo.ScriptName -match 'PSReadLine' -and `$_.FullyQualifiedErrorId -eq 'NotSupportedException') {
                continue
            }

            if (`$_.ErrorDetails.RecommendedAction -ne 'Silent') {
                Write-Error -ErrorRecord `$_ -ErrorAction Continue
            }

            `$Script:DisplayedErrorLog.Add(`$_)
        } elseif (`$_ -is [System.Management.Automation.InformationRecord] -and `$_.Tags -contains 'AMT.ErrorDisplay') {
            `$CapturedErr = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(`$_.MessageData.ToString()),
                'AMT.ErrorDisplay',
                [System.Management.Automation.ErrorCategory]::NotSpecified,
                `$null
            )
            Write-Error -ErrorRecord `$CapturedErr -ErrorAction Continue
            `$Script:DisplayedErrorLog.Add(`$CapturedErr)
        } elseif (`$_ -is [System.Management.Automation.InformationRecord]) {
            # Pass through untagged info records (normal info-stream output)
            Write-Information -MessageData `$_.MessageData -Tags `$_.Tags -InformationAction Continue
        } else {
            # Pass through all other output (stdout objects, etc.)
            Write-Output `$_
        }
    }
} catch {
    `$TerminatingError = `$_
    `$ExceptionMessage = if (`$TerminatingError.Exception) { `$TerminatingError.Exception.Message } else { 'Unknown exception' }
    `$FullyQualifiedErrorId = if (`$TerminatingError.FullyQualifiedErrorId) { `$TerminatingError.FullyQualifiedErrorId } else { 'Unavailable' }
    `$PositionMessage = if (`$TerminatingError.InvocationInfo -and `$TerminatingError.InvocationInfo.PositionMessage) { `$TerminatingError.InvocationInfo.PositionMessage.Trim() } else { 'Unavailable' }
    `$StackTraceMessage = if (`$TerminatingError.ScriptStackTrace) { `$TerminatingError.ScriptStackTrace.Trim() } elseif (`$TerminatingError.Exception -and `$TerminatingError.Exception.StackTrace) { `$TerminatingError.Exception.StackTrace.Trim() } else { 'Unavailable' }
    Write-Error ("Terminating error in script '$ScriptPath': `$ExceptionMessage`nFQID: `$FullyQualifiedErrorId`nPosition: `$PositionMessage`nStack: `$StackTraceMessage")
    `$Script:DisplayedErrorLog.Add(`$TerminatingError)
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
                        if (-not $capturedErrors.GetType().IsArray) {
                            $capturedErrors = @($capturedErrors)
                        }

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
                Get-ChildItem -Path $argPattern -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue -WhatIf:$False

                if ($DebugPreference -eq 'Ignore') {
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
            $ArgSplat = @{ };
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
        $Env:PSModulePath = $Script:OriginalPSModulePath;
        $Script:REMOVE_ORDER | ForEach-Object { Get-Module -Name $_ | Remove-Module -Force -WhatIf:$False; }
        if ($Script:TransientScriptPath -and (Test-Path -Path $Script:TransientScriptPath -PathType Leaf)) {
            Remove-Item -Path $Script:TransientScriptPath -Force -ErrorAction SilentlyContinue -WhatIf:$False;
        }
    }
} end {
    Remove-Variable -Name CompiledScript -Scope Global -WhatIf:$False -ErrorAction SilentlyContinue;
}
