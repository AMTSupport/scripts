#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -PSEdition Desktop

# remove admin from accounts expect localadmin and domain admin (input argument: $admin)
# if there were no accounts modified return 0, otherwise return 1 so the script will display as failed in the n-able dashboard

Param(
    [Parameter()]
    [String]$LocalAdmin = "localadmin",

    [Parameter()]
    [String[]]$UserExceptions = @()
)

function Get-LocalAdmins {
    $Admins = net localgroup administrators
    $Admins = $Admins[6..($Admins.Length - 3)]
    $Admins = $Admins | ForEach-Object { $_.Trim() }
    $Admins = $Admins | Where-Object { $_ -notin ("nt authority\system", "administrator") }

    return $Admins
}

function Remove-Admins([Parameter(Mandatory)][String[]]$Users) {
    Write-Host "Received Users: $Users"
    $Removing = $Users | Where-Object { $_ -notin (@($LocalAdmin) + $UserExceptions) }
    Write-Host "Removing Users: $Removing"

    $Removing | ForEach-Object {
        Write-Host "Removing $_ from administrators group"
        net localgroup administrators /del $_
    }
}

function Main {
    $Global:ErrorActionPreference = "Stop"
    $Global:VerbosePreference = "Continue"


    $LocalAdmins = Get-LocalAdmins
    $RemovedAdmins = Remove-Admins -Users $LocalAdmins

    if ($RemovedAdmins.Count -eq 0) {
        Write-Host "No accounts modified"
        return 0
    } else {
        Write-Host "Accounts modified: $RemovedAdmins"
        return 1
    }
}

Main
