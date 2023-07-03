<#
.SYNOPSIS
  Disable AutoRun for all drives
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

Param (
    [System.Object[]]$RegistryValues=@(
        [RegistryValue]::new(
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer",
            "NoDriveTypeAutorun",
            "DWord",
            "255"
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
