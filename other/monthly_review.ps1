Param(
    [Parameter()]
    [String]$ClientName,

    [Parameter(DontShow)]
    [String]$SharedFolder = ($MyInvocation.MyCommand.PSScriptRoot | Split-Path -Parent | Split-Path -Parent) # Maybe just get the folder after the username?
)

function Invoke-Script($Name, $Params) {
    $Script = "$($MyInvocation.PSScriptRoot)/$Name.ps1"

    if (-not (Test-Path $Script)) {
        Write-Host "Script not found: $Script"
        Exit 1001
    }

    Write-Host "Running $Script with params $Params"
    & $Script @Params
}

function Get-MFAChanges {
    Invoke-Script "mfa_compare" @{
        ClientName = $ClientName
        SharedFolder = $SharedFolder
    }
}

function Get-NewDevices {
    # Get new devices in the last 30 days
}

function Get-Alerts {
    # Get alerts from the last 30 days
}

function Get-
