#Requires -Version 5.1

Using module ..\..\common\Environment.psm1
Using module ..\..\common\Logging.psm1
Using module ..\..\common\Input.psm1
Using module ..\..\common\Ensure.psm1
Using module ..\..\common\Utils.psm1
Using module ..\..\common\PackageManager.psm1
Using module ..\..\common\UsersAndAccounts.psm1
Using module ..\..\common\Registry.psm1

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter()]
    [String]$WireGuardPackage = 'wireguard'
)

Invoke-RunMain $PSCmdlet {
    Invoke-EnsureAdministrator;

    # Install Package if not already installed.
    Invoke-Info 'Installing WireGuard...';
    if (-not (Test-ManagedPackage 'WireGuard')) {
        Install-ManagedPackage -PackageName 'WireGuard';
    }

    Invoke-Info 'Setting up LimitedOperatorUI Registry Key...';
    Set-RegistryKey -Path HKLM:\SOFTWARE\WireGuard -Key 'LimitedOperatorUI' -Value 1 -Kind DWord;

    # Query for if any users need to be added to Network Configuration Operators
    Invoke-Info 'Querying for if any users need to be added to Network Configuration Operators...';
    if (Get-UserConfirmation -Title 'Add Users' -Question 'Do you want to add any users to Network Configuration Operators?' -Default $True) {
        Invoke-Info 'Preparing to add users to Network Configuration Operators, this may take a while...';

        [ADSI]$Local:Group = Get-Group 'Network Configuration Operators';
        [ADSI]$Local:UserGroup = Get-Group 'Users';
        [HashTable[]]$Local:Users = Get-MembersOfGroup $Local:UserGroup | ForEach-Object {
            [PSCustomObject]$Local:Formatted = Format-ADSIUser $_;
            @{
                ADSI      = $_;
                Formatted = "$($Local:Formatted.Domain)\$($Local:Formatted.Name)";
            };
        };
        while ($True) {
            [HashTable]$Local:User = Get-UserSelection `
                -Title 'Select User' `
                -Question 'Select the user you want to add to Network Configuration Operators:' `
                -Choices $Local:Users `
                -FormatChoice { param($User) $User.Formatted };

            $null = Add-MemberToGroup -Group $Local:Group -User $Local:User.ADSI;
            $Local:Users = $Local:Users | Where-Object { $_ -ne $Local:User };

            if ($Local:Users.Count -eq 0) {
                Invoke-Debug 'No more users to add to Network Configuration Operators.';
                break;
            }

            if (Get-UserConfirmation -Title 'Add another user?' -Question 'Do you want to add another user to Network Configuration Operators?' -Default $True) {
                continue;
            } else {
                break;
            }
        }
    }
};
