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
        New-Item -Path $Local:PrivatePSModulePath -ItemType Directory -Force -WhatIf:$False | Out-Null;
    }

    $Script:OriginalPSModulePath = $Env:PSModulePath;
    $Local:PSModulePathSeparator = [System.IO.Path]::PathSeparator;
    if (-not ($Env:PSModulePath -like "*$Local:PrivatePSModulePath*")) {
        $Env:PSModulePath = "$Local:PrivatePSModulePath$Local:PSModulePathSeparator" + $Env:PSModulePath;
    }

    # Must use UTF-8 Bom for PS < 6 to properly handle Unicode characters.
    $Local:PSBelow6 = $PSVersionTable.PSVersion.Major -lt 6;
    $Local:Bom = [Byte[]](0xEF, 0xBB, 0xBF);
    $Local:Encoding = 'UTF8';
    [Int]$Script:ModuleLockTimeoutSeconds = 180;
    [Int]$Script:ModuleLockRetryMilliseconds = 200;

    function Test-UTF8ModuleReady {
        [CmdletBinding()]
        [OutputType([Boolean])]
        param(
            [Parameter(Mandatory)]
            [String]$ModulePath,

            [Parameter(Mandatory)]
            [String]$ReadyPath,

            [Parameter(Mandatory)]
            [Byte[]]$Bom,

            [Parameter(Mandatory)]
            [Boolean]$PSBelow6
        )

        if (-not (Test-Path -Path $ReadyPath -PathType Leaf)) {
            return $false;
        }

        $Local:Params = @{ Path = $ModulePath; TotalCount = $Bom.Length; };
        if ($PSBelow6) { $Local:Params.Add('Encoding', 'Byte'); } else { $Local:Params.Add('AsByteStream', $True); }

        $Local:WantBom = $PSBelow6;
        $Local:IsBomEncoded = [Collections.Generic.SortedSet[String]]::CreateSetComparer().Equals((Get-Content @Local:Params), $Bom);
        return $Local:WantBom -eq $Local:IsBomEncoded;
    }

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

            [Parameter(Mandatory)]
            [ValidateSet('UTF8String', 'Zip')]
            [String]$ModuleType,

            [String]$ModulePath,

            [String]$ReadyPath,

            [String]$ModuleFolderPath,

            [Byte[]]$Bom,

            [Boolean]$PSBelow6,

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
                $Local:IsReady = switch ($ModuleType) {
                    'UTF8String' { Test-UTF8ModuleReady -ModulePath $ModulePath -ReadyPath $ReadyPath -Bom $Bom -PSBelow6:$PSBelow6; break; }
                    'Zip' { Test-ZipModuleReady -ReadyPath $ReadyPath -ModuleFolderPath $ModuleFolderPath; break; }
                }

                if ($Local:IsReady) {
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

            [Parameter(Mandatory)]
            [ValidateSet('UTF8String', 'Zip')]
            [String]$ModuleType,

            [String]$ModulePath,

            [String]$ReadyPath,

            [String]$ModuleFolderPath,

            [Byte[]]$Bom,

            [Boolean]$PSBelow6,

            [Boolean]$OperationSucceeded = $false
        )

        try {
            $Local:OwnerSucceeded = $OperationSucceeded;
            $Local:IsReady = $false;

            switch ($ModuleType) {
                'UTF8String' {
                    if ($Local:OwnerSucceeded -and $ReadyPath -and -not (Test-Path -Path $ReadyPath -PathType Leaf)) {
                        $Local:HasValidContent = $false;
                        if (Test-Path -Path $ModulePath -PathType Leaf) {
                            $Local:BomParams = @{ Path = $ModulePath; TotalCount = $Bom.Length };
                            if ($PSBelow6) { $Local:BomParams.Add('Encoding', 'Byte') } else { $Local:BomParams.Add('AsByteStream', $True) }
                            $Local:IsBomEncoded = [Collections.Generic.SortedSet[String]]::CreateSetComparer().Equals((Get-Content @Local:BomParams), $Bom);
                            $Local:HasValidContent = $PSBelow6 -eq $Local:IsBomEncoded;
                        }

                        if ($Local:HasValidContent) {
                            Set-Content -Path $ReadyPath -Value ([DateTime]::UtcNow.ToString('o')) -Encoding UTF8 -Force -WhatIf:$False;
                        }
                    }

                    if (Test-Path -Path $ReadyPath -PathType Leaf) {
                        $Local:IsReady = Test-UTF8ModuleReady -ModulePath $ModulePath -ReadyPath $ReadyPath -Bom $Bom -PSBelow6:$PSBelow6;
                    }
                    break;
                }
                'Zip' {
                    if ($Local:OwnerSucceeded -and $ReadyPath -and $ModuleFolderPath -and -not (Test-Path -Path $ReadyPath -PathType Leaf)) {
                        $Local:ModuleFiles = Get-ChildItem -Path $ModuleFolderPath -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.ready' };
                        if ($null -ne $Local:ModuleFiles -and $Local:ModuleFiles.Count -gt 0) {
                            Set-Content -Path $ReadyPath -Value ([DateTime]::UtcNow.ToString('o')) -Encoding UTF8 -Force -WhatIf:$False;
                        }
                    }

                    if ($Local:OwnerSucceeded) {
                        $Local:IsReady = Test-ZipModuleReady -ReadyPath $ReadyPath -ModuleFolderPath $ModuleFolderPath;
                    }
                    break;
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

    $Script:ScriptPath;
    $Script:TransientScriptPath;

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
            New-Item -Path $Local:ModuleFolderPath -ItemType Directory -Force -WhatIf:$False | Out-Null;
        }

        $Local:ModuleLockPath = Join-Path -Path $Local:PrivatePSModulePath -ChildPath "$Local:NameHash.lock";
        $Local:ModuleReadyPath = Join-Path -Path $Local:ModuleFolderPath -ChildPath '.ready';

        switch ($_.Type) {
            'UTF8String' {
                $Local:IsRootScript = $null -eq $Script:ScriptPath;
                $Local:FileSuffix = if ($Local:IsRootScript) { 'ps1' } else { 'psm1' };
                $Local:InnerModulePath = Join-Path -Path $Local:ModuleFolderPath -ChildPath "$Local:NameHash.$Local:FileSuffix";

                if ($Local:IsRootScript) {
                    $Local:RootScriptPath = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.ps1');
                    Write-Verbose "Writing root script content to temp file: $Local:RootScriptPath"
                    Set-Content -Path $Local:RootScriptPath -Value $Content -Encoding $Local:Encoding -Force -WhatIf:$False;
                    $Script:ScriptPath = $Local:RootScriptPath;
                    $Script:TransientScriptPath = $Local:RootScriptPath;
                    return;
                }

                if (-not (Test-UTF8ModuleReady -ModulePath $Local:InnerModulePath -ReadyPath $Local:ModuleReadyPath -Bom $Local:Bom -PSBelow6:$Local:PSBelow6)) {
                    [Boolean]$Local:Utf8Succeeded = $false;
                    $Local:LockHandle = Wait-ModuleLock -LockPath $Local:ModuleLockPath -ModuleName $Local:Name -ModuleHash $Local:Hash -ModuleType 'UTF8String' -ModulePath $Local:InnerModulePath -ReadyPath $Local:ModuleReadyPath -Bom $Local:Bom -PSBelow6:$Local:PSBelow6;
                    try {
                        if (-not (Test-UTF8ModuleReady -ModulePath $Local:InnerModulePath -ReadyPath $Local:ModuleReadyPath -Bom $Local:Bom -PSBelow6:$Local:PSBelow6)) {
                            Write-Verbose "Writing content to module file: $Local:InnerModulePath"
                            Set-Content -Path $Local:InnerModulePath -Value $Content -Encoding $Local:Encoding -Force -WhatIf:$False;
                            $Local:Utf8Succeeded = $true;
                        } else {
                            $Local:Utf8Succeeded = $true;
                        }
                    } finally {
                        Complete-ModuleLock -LockHandle $Local:LockHandle -LockPath $Local:ModuleLockPath -ModuleType 'UTF8String' -ModulePath $Local:InnerModulePath -ReadyPath $Local:ModuleReadyPath -Bom $Local:Bom -PSBelow6:$Local:PSBelow6 -OperationSucceeded $Local:Utf8Succeeded;
                    }
                }
            }

            'Zip' {
                if (-not (Test-ZipModuleReady -ReadyPath $Local:ModuleReadyPath -ModuleFolderPath $Local:ModuleFolderPath)) {
                    $Local:LockHandle = Wait-ModuleLock -LockPath $Local:ModuleLockPath -ModuleName $Local:Name -ModuleHash $Local:Hash -ModuleType 'Zip' -ReadyPath $Local:ModuleReadyPath -ModuleFolderPath $Local:ModuleFolderPath;
                    [String]$Local:TempFile = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.zip');
                    try {
                        if (-not (Test-ZipModuleReady -ReadyPath $Local:ModuleReadyPath -ModuleFolderPath $Local:ModuleFolderPath)) {
                            Write-Verbose "Preparing zip module folder: $Local:ModuleFolderPath"
                            Get-ChildItem -Path $Local:ModuleFolderPath -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.ready' } | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue -WhatIf:$False;

                            [Byte[]]$Local:Bytes = [System.Convert]::FromBase64String($Content);
                            [System.IO.File]::WriteAllBytes($Local:TempFile, $Local:Bytes);

                            Write-Verbose "Expanding module file: $Local:TempFile to $Local:ModuleFolderPath"
                            try {
                                Expand-Archive -Path $Local:TempFile -DestinationPath $Local:ModuleFolderPath -Force -WhatIf:$False -ErrorAction Stop;
                                $Local:ZipSucceeded = $true;
                                Write-Verbose "Expanded module file successfully: $Local:TempFile"
                            } catch {
                                Write-Error "Failed to expand module archive '$Local:TempFile' to '$Local:ModuleFolderPath': $($_.Exception.Message)"
                                throw;
                            }
                        } else {
                            $Local:ZipSucceeded = $true;
                        }
                    } finally {
                        if (Test-Path -Path $Local:TempFile) {
                            Remove-Item -Path $Local:TempFile -Force -ErrorAction SilentlyContinue -WhatIf:$False;
                        }

                        Complete-ModuleLock -LockHandle $Local:LockHandle -LockPath $Local:ModuleLockPath -ModuleType 'Zip' -ReadyPath $Local:ModuleReadyPath -ModuleFolderPath $Local:ModuleFolderPath -OperationSucceeded $Local:ZipSucceeded;
                    }
                }
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
    & "$ScriptPath" @ArgSplat 2>&1 | ForEach-Object {
        if (`$_ -is [System.Management.Automation.ErrorRecord]) {
            if (`$_.ErrorDetails.RecommendedAction -ne 'Silent') {
                Write-Error -ErrorRecord `$_ -ErrorAction Continue
            }

            `$Script:DisplayedErrorLog.Add(`$_)
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
        $Env:PSModulePath = $Script:OriginalPSModulePath;
        $Script:REMOVE_ORDER | ForEach-Object { Get-Module -Name $_ | Remove-Module -Force -WhatIf:$False; }
        if ($Script:TransientScriptPath -and (Test-Path -Path $Script:TransientScriptPath -PathType Leaf)) {
            Remove-Item -Path $Script:TransientScriptPath -Force -ErrorAction SilentlyContinue -WhatIf:$False;
        }
    }
} end {
    Remove-Variable -Name CompiledScript -Scope Global -WhatIf:$False -ErrorAction SilentlyContinue;
}
