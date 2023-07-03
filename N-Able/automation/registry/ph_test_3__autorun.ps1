<#
.SYNOPSIS
  Disable AutoRun for all drives
.PARAMETER ScriptLogLocation - not used for N-Able RMM
    The directory in which you would like the log file.
.PARAMETER LogFileName
    The name (with extension) you would like for the log file.
.PARAMETER RegPath
    The path to the registry key that will contain this value.
.PARAMETER ValueName
    The name of the registry value being added or changed.
.PARAMETER ValueType
    The type of registry value being added or changed.
.PARAMETER Value
    The registry value.
.PARAMETER RestartSpooler
    Restart the spooler service after adding the registry key?
.INPUTS
  None
.OUTPUTS
  Log file stored in location specified in parameters.
.NOTES
  Version:        1.0
  Author:         Phil Haddock
  Creation Date:  16th July 2021
  Purpose/Change: Initial script development
#>

# Parameters
Param (
#    [string]$ScriptLogLocation = "C:\Temp2",
#    [string]$LogFileName = "RemediatePrintNightmare.log",
    [string]$RegPath = "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer",
    [string]$ValueName = "NoDriveTypeAutorun",
    [string]$ValueType = "DWord",
    [string]$Value = "255",
    [string]$Result
)

# Start Logging (path will be created if it doesn't already)
#Start-Transcript -Path (Join-Path $ScriptLogLocation $LogFileName) -Append

# Check if the registry key exists
$KeyTest = Test-Path $RegPath

if($KeyTest){
    # Update the create/update the value
    New-ItemProperty -Path $RegPath -Name $ValueName -Value $Value -PropertyType $ValueType -Force
    $Result="Key found"
}
else{
    # Add the registry key
    New-Item -Path $RegPath -Force
    # Update the create/update the value
    New-ItemProperty -Path $RegPath -Name $ValueName -Value $Value -PropertyType $ValueType -Force
    $Result="Key not found - creating"
}

Write-Host $Result
# Stop Logging
#Stop-Transcript