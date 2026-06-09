#Requires -Version 5.1

Using module .\Logging.psm1

<#
.SYNOPSIS
    Gets the path to a lock file in the system temp directory.

.DESCRIPTION
    Returns a path like $TempPath\AMT_$ScriptName_$ResourceId.lock.
    If ScriptName is not provided, derives it from the caller's script file.

.PARAMETER ScriptName
    The name of the script requesting the lock. If omitted, derived from stack.

.PARAMETER ResourceId
    The resource identifier (e.g. manufacturer name) to include in the lock file name.
#>
function Get-LockPath {
    param(
        [String]$ScriptName,
        [Parameter(Mandatory)][String]$ResourceId
    )
    if (-not $ScriptName) {
        [System.Management.Automation.CallStackFrame]$Caller = (Get-PSCallStack)[1];
        $ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($Caller.InvocationInfo.ScriptName);
    }
    $SanitizedScript = $ScriptName -replace '[^a-zA-Z0-9]', '';
    $Sanitized = $ResourceId -replace '[^a-zA-Z0-9]', '';
    return [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "AMT_${SanitizedScript}_${Sanitized}.lock");
}

<#
.SYNOPSIS
    Acquires an exclusive lock on a lock file.

.DESCRIPTION
    Waits up to 600 seconds to acquire an exclusive write lock on the specified path.
    Writes metadata (PID, optional owner, timestamp) to the file.
    Returns the file handle.

.PARAMETER LockPath
    Full path to the lock file.

.PARAMETER LockOwner
    Optional owner name written to the lock file metadata.
#>
function Wait-LockFile {
    param(
        [Parameter(Mandatory)][String]$LockPath,
        [String]$LockOwner
    )
    [Int]$TimeoutSeconds = 600;
    [Int]$RetryMs = 1000;
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew();
    $LockDir = Split-Path -Path $LockPath -Parent;
    if (-not (Test-Path -Path $LockDir)) {
        New-Item -Path $LockDir -ItemType Directory -Force -WhatIf:$False | Out-Null;
    }
    while ($true) {
        try {
            $Handle = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None);
            $Handle.SetLength(0);
            $Content = "PID=$PID";
            if ($LockOwner) { $Content += "`nOwner=$LockOwner"; }
            $Content += "`nStarted=$([DateTime]::UtcNow.ToString('o'))";
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Content);
            $Handle.Write($Bytes, 0, $Bytes.Length);
            $Handle.Flush();
            return $Handle;
        } catch [System.IO.IOException] {
            if ($Stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                throw "Timed out waiting for lock file '$LockPath' after ${TimeoutSeconds}s.";
            }
            $Elapsed = [Math]::Floor($Stopwatch.Elapsed.TotalSeconds);
            Invoke-Info "Waiting for another instance to release lock '${LockPath}' (${Elapsed}s elapsed)...";
            Start-Sleep -Milliseconds $RetryMs;
        }
    }
}

<#
.SYNOPSIS
    Releases a lock file handle and removes the lock file.

.DESCRIPTION
    Safely closes the handle and deletes the lock file. Handles nulls and missing files.

.PARAMETER LockHandle
    The file handle returned by Wait-LockFile.

.PARAMETER LockPath
    Full path to the lock file.
#>
function Release-LockFile {
    param([System.IDisposable]$LockHandle, [String]$LockPath)
    if ($LockHandle) {
        try { $LockHandle.Close(); } catch { }
    }
    if ($LockPath -and (Test-Path -Path $LockPath)) {
        try { Remove-Item -Path $LockPath -Force -ErrorAction SilentlyContinue; } catch { }
    }
}

<#
.SYNOPSIS
    Acquires a lock, executes a script block, and releases the lock.

.DESCRIPTION
    Derives the script name from the caller, builds the lock path, acquires the lock,
    executes the script block with optional arguments, and releases the lock in finally.

.PARAMETER ResourceId
    The resource identifier for the lock file name.

.PARAMETER ScriptBlock
    The script block to execute under lock.

.PARAMETER ArgumentList
    Optional arguments to splat to the script block.
#>
function Invoke-UnderLock {
    param(
        [Parameter(Mandatory)][String]$ResourceId,
        [Parameter(Mandatory)][ScriptBlock]$ScriptBlock,
        [Object[]]$ArgumentList
    )
    [System.Management.Automation.CallStackFrame]$Caller = (Get-PSCallStack)[1];
    $ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($Caller.InvocationInfo.ScriptName);
    $LockPath = Get-LockPath -ScriptName $ScriptName -ResourceId $ResourceId;
    $Handle = $null;
    try {
        $Handle = Wait-LockFile -LockPath $LockPath -LockOwner $ResourceId;
        if ($ArgumentList) {
            & $ScriptBlock @ArgumentList;
        } else {
            & $ScriptBlock;
        }
    } finally {
        Release-LockFile -LockHandle $Handle -LockPath $LockPath;
    }
}

Export-ModuleMember -Function Get-LockPath, Wait-LockFile, Release-LockFile, Invoke-UnderLock;
