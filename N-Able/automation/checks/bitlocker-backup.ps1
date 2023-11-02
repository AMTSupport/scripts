#Requires -Version 5.1
#Requires -Modules BitLocker

#region - Error Codes

$Script:ERROR_BITLOCKER_DISABLED = 1001
$Script:ERROR_NO_RECOVERY_PASSWORD = 1002
$Script:ERROR_UNKNOWN = 9999

#endregion - Error Codes

function Main {
    $AllProtectors = (Get-BitlockerVolume -MountPoint $env:SystemDrive).KeyProtector

    if ($null -eq $AllProtectors -or $AllProtectors.Count -eq 0) {
        [Console]::Error.WriteLine("BitLocker is not enabled on the system drive.")
        exit $Script:ERROR_BITLOCKER_DISABLED
    }

    $RecoveryProtector = ($AllProtectors | where-object { $_.KeyProtectorType -eq "RecoveryPassword" })

    if ($null -eq $RecoveryProtector) {
        [Console]::Error.WriteLine("BitLocker is not configured to use a recovery password.")
        exit $Script:ERROR_NO_RECOVERY_PASSWORD
    }

    try {
        BackupToAAD-BitLockerKeyProtector -MountPoint $env:SystemDrive -KeyProtectorId $RecoveryProtector.KeyProtectorID
    } catch {
        [Console]::Error.WriteLine("An unknown error occurred.")
        [Console]::Error.WriteLine($_.Exception.Message)
        exit $Script:ERROR_UNKNOWN
    }

    [Console]::Write("BitLocker successfully recovery key backed up to Azure AD.")
}

Main
