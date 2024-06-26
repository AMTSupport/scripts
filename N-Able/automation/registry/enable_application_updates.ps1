#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
  Ensures that the internal auto-update behaviour of these applications is not disabled.
#>

Param (
    [System.Object[]]$RegistryValues=@(
        # Google Chrome
        [RegistryValue]::new(
            "HKLM:\SOFTWARE\Policies\Google\Update",
            "Update{8A69D345-D564-463C-AFF1-A69D9E530F96}",
            "DWord",
            "1"
        ),
        [RegistryValue]::new(
            "HKLM:\SOFTWARE\Policies\Google\Update",
            "Update{4DC8B4CA-1BDA-483E-B5FA-D3C12E15B62D}",
            "DWord",
            "1"
        ),
        [RegistryValue]::new(
            "HKLM:\SOFTWARE\Policies\Google\Update",
            "Update{8BA986DA-5100-405E-AA35-86F34A02ACBF}",
            "DWord",
            "1"
        ),
        [RegistryValue]::new(
            "HKLM:\SOFTWARE\Policies\Google\Update",
            "UpdateDefault",
            "DWord",
            "1"
        ),
        # Zoom
        [RegistryValue]::new(
            "HKLM:\SOFTWARE\Policies\Zoom\Zoom Meetings\General",
            "EnableClientAutoUpdate",
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
