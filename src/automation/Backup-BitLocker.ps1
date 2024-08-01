#Requires -Version 5.1
#Requires -Modules BitLocker

Import-Module $PSScriptRoot/../common/Environment.psm1;
Invoke-RunMain $PSCmdlet {
    Invoke-EnsureAdministrator;

    #region - Error Codes

    $Script:ERROR_BITLOCKER_DISABLED = Register-ExitCode 'BitLocker is not enabled on the system drive.';
    $Script:ERROR_NO_RECOVERY_PASSWORD = Register-ExitCode 'BitLocker is not configured to use a recovery password.';
    $Script:ERROR_DURING_UPLOAD = Register-ExitCode 'An error occurred while uploading the recovery key to Azure AD.';

    #endregion - Error Codes

    # Safety: This should never have a null value, as we are using the system drive environment variable.
    [Microsoft.BitLocker.Structures.BitLockerVolume]$Local:Volume = Get-BitLockerVolume -MountPoint $env:SystemDrive;
    [Microsoft.BitLocker.Structures.BitLockerVolumeKeyProtector]$Local:RecoveryProtector = ($Local:Volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq [Microsoft.BitLocker.Structures.BitLockerVolumeKeyProtectorType]::RecoveryPassword });

    if (($Local:Volume.ProtectionStatus -eq 'Off') -or $Local:Volume.KeyProtector.Count -eq 0) {
        Invoke-failedExit -ExitCode $Script:ERROR_BITLOCKER_DISABLED;
    }

    if ($null -eq $Local:RecoveryProtector) {
        Invoke-failedExit -ExitCode $Script:ERROR_NO_RECOVERY_PASSWORD;
    }

    try {
        BackupToAAD-BitLockerKeyProtector -MountPoint $env:SystemDrive -KeyProtectorId $Local:RecoveryProtector.KeyProtectorID | Out-Null;
        Invoke-Info 'BitLocker recovery key successfully backed up to Azure AD.';
    }
    catch {
        Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:ERROR_DURING_UPLOAD;
    }
};
