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

#Requires -Version 5.1
#Requires -RunAsAdministrator

Param (
    [System.Object[]]$RegistryValues=@(
        [RegistryValue]::new(
            "HKLM:\SYSTEM\CurrentControlSet\Control\LSA\",
            "RestrictAnonymous",
            "DWord",
            "1"
        ),
        [RegistryValue]::new(
            "HKLM:\SYSTEM\CurrentControlSet\Services\lanmanserver\parameters",
            "restrictnullsessaccess",
            "DWord",
            "1"
        )
    ),

    [Parameter(HelpMessage = "If dry run is enabled, no changes will be made to the system.")]
    [switch]$dryrun
)

class RegistryValue {
    [string]$RegPath
    [string]$ValueName
    [string]$ValueType
    [string]$Value

    RegistryValue([string]$RegPath, [string]$ValueName, [string]$ValueType, [string]$Value) {
        $this.RegPath = $RegPath
        $this.ValueName = $ValueName
        $this.ValueType = $ValueType
        $this.Value = $Value
    }

    [String] ToString() {
        return "$($this.RegPath)`:$($this.ValueName)"
    }
}

function Get-Parameters {
    if ($dryrun) {
        Write-Host "Dry run mode enabled; No changes will be made to the system."
        Write-Host "RegPath: $RegPath"
        Write-Host "ValueName: $ValueName"
        Write-Host "ValueType: $ValueType"
        Write-Host "Value: $Value"
    }
}

function New-RegistryKey([Parameter(Mandatory=$true)] [RegistryValue]$value) {
    try {
        Get-ItemProperty -Path $value.RegPath -Name $value.ValueName -ErrorAction Stop | Out-Null
        Write-Host "Existing registry key ``$($value.toString())`` found."
    }
    catch {
        Write-Host "Creating registry key ``$($value.toString())``"
        if ($dryrun -eq $false) {
            New-Item -Path $value.RegPath -Force | Out-Null
        }
    }
}

function Set-RegistryValue([Parameter(Mandatory=$true)] [RegistryValue]$value) {
    $existingValue = try {
        Get-ItemProperty -Path $value.RegPath -Name $value.ValueName -ErrorAction Stop | Select-Object -ExpandProperty $value.ValueName
    } catch {
        Write-Host "The registry value ``$($value.toString())`` does not have an existing value."
        $null
    }

    if ($existingValue -eq $value.Value) {
        Write-Host "Registry value ``$($value.toString())`` is already set to ``$($value.Value)``"
        return
    }

    Write-Host "Updating registry value from ``$existingValue`` to ``$($value.Value)``"
    if ($dryrun -eq $false) {
        New-ItemProperty -Path $value.RegPath -Name $value.ValueName -Value $value.Value -PropertyType $value.ValueType -Force | Out-Null
    }
}

function Main {
    Get-Parameters

    foreach ($registryValue in $RegistryValues) {
        New-RegistryKey $registryValue
        Set-RegistryValue $registryValue
    }
}

Main
