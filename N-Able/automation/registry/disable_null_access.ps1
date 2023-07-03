<#
.SYNOPSIS
  Disable Null Login

Set
HKLM\SYSTEM\CurrentControlSet\Control\LSA\RestrictAnonymous=1
HKLM\SYSTEM\CurrentControlSet\Services\lanmanserver\parameters\restrictnullsessaccess=1
Reboot required after setting these

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
    [string]$RegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\LSA\",
    [string]$ValueName = "RestrictAnonymous",
    [string]$ValueType = "DWord",
    [string]$Value = "1",
    [string]$Result
)

function Test-RegistryValue {

param (
 [parameter(Mandatory=$true)]
 [ValidateNotNullOrEmpty()]$Path,

[parameter(Mandatory=$true)]
 [ValidateNotNullOrEmpty()]$Value
)

#write-host Starting function
#write-host Path $Path
#Write-Host $ValueName

try {

Get-ItemProperty -Path $Path -Name $ValueName -ErrorAction Stop|Out-Null
write-host True $Path
 return $true
 }

catch {

Write-Host false $Path
return $false

}

}

# Start Logging (path will be created if it doesn't already exist.  Doesn't work with RMM)
#Start-Transcript -Path (Join-Path $ScriptLogLocation $LogFileName) -Append

# Check if the registry key exists
#$KeyTest = Test-Path $RegPath
$KeyTest = Test-RegistryValue $RegPath $ValueName

if($KeyTest){
    # Update the value
    New-ItemProperty -Path $RegPath -Name $ValueName -Value $Value -PropertyType $ValueType -Force
    $Result="Key found: RestrictAnonymous-Updated to 1"
}
else{
    # Add the registry key
    New-Item -Path $RegPath -Force
    # Create/update the value
    New-ItemProperty -Path $RegPath -Name $ValueName -Value $Value -PropertyType $ValueType -Force
    $Result="Key not found: RestrictAnonymous-creating"
}

Write-Host $Result

$RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\lanmanserver\parameters"
$ValueName = "restrictnullsessaccess"
$ValueType = "DWord"
$Value = "1"

$KeyTest = Test-RegistryValue $RegPath $ValueName

if($KeyTest){
    # Update the value
    New-ItemProperty -Path $RegPath -Name $ValueName -Value $Value -PropertyType $ValueType -Force
    $Result="Key found: restrictnullsessaccess-Updated to 1"
}
else{
    # Add the registry key
    New-Item -Path $RegPath -Force
    # Create/update the value
    New-ItemProperty -Path $RegPath -Name $ValueName -Value $Value -PropertyType $ValueType -Force
    $Result="Key not found: restrictnullsessaccess-creating"
}

Write-Host $Result


Exit 0

# Stop Logging
#Stop-Transcript
