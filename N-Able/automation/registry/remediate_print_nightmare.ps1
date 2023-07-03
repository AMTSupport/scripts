<#
.SYNOPSIS
  Sets the registry value for "Allow Print Spooler to accept client connections" group policy and restarts the spooler service.
.DESCRIPTION
  Sets the registry value for "Allow Print Spooler to accept client connections" group policy. This is Microsoft's recommendation for the zero day (CVE-2021-34527 - https://msrc.microsoft.com/update-guide/vulnerability/CVE-2021-34527).
.PARAMETER ScriptLogLocation
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
  Author:         Jason Beer
  Creation Date:  7/6/2021
  Purpose/Change: Initial script development
.EXAMPLE
  Remediate-PrintNightmare -ScriptLogLocation "C:\ExampleFolder\Remediate-PrintNightmare" -RegPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers" -ValueName "RegisterSpoolerRemoteRpcEndPoint" -ValueType "DWord" -Value "2" -RestartSpooler $True
#>

# Parameters
Param (
#    [string]$ScriptLogLocation = "C:\Temp2",
#   [string]$LogFileName = "RemediatePrintNightmare.log",
    [string]$RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint",
    [string]$ValueName = "NoWarningNoElevationOnInstall",
    [string]$ValueType = "DWord",
    [string]$Value = "0",
    [string]$Result,
    [bool]$Keytest
    )

# Start Logging (path will be created if it doesn't already)
#Start-Transcript -Path (Join-Path $ScriptLogLocation $LogFileName) -Append

# Check if the registry key exists
$KeyTest = Test-Path $RegPath

if($KeyTest){
    # Add the registry key
    New-Item -Path $RegPath -Force
    # Update the create/update the value
    New-ItemProperty -Path $RegPath -Name $ValueName -Value $Value -PropertyType $ValueType -Force
    $Result="Point and Print key found.  Value NoWarningNoElevationOnInstall set"
  
}
else{
# Do nothing
    $Result="Point and Print key not found. No action required"
}

Write-Host $Result
Exit 0
# Stop Logging
#Stop-Transcript