#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter()]
    [String]$WireGuardPackage = 'wireguard'
)

Import-Module $PSScriptRoot/../../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    Invoke-EnsureAdministrator;

    # Install Package if not already installed.
    if (-not (Test-Package -PackageName $WireGuardPackage)) {
        Install-ManagedPackage -PackageName wireguard;
    }

    Invoke-Info 'Setting up LimitedUI Registry Key...';
    Set-RegistryKey -Path HKLM:\SOFTWARE\WireGuard -Key 'LimitedUserUI' -Value 1 -Kind DWord;

    # Query for if any users need to be added to Network Configuration Operators
    Invoke-Info 'Querying for if any users need to be added to Network Configuration Operators...';
    if (Get-UserConfirmation -Title 'Add Users' -Question 'Do you want to add any users to Network Configuration Operators?' -Default $True) {
        Invoke-Info 'Preparing to add users to Network Configuration Operators, this may take a while...';


        [ADSI]$Local:Group = Get-Group 'Network Configuration Operators';
        [ADSI[]]$Local:Users = Get-GroupMembers "Users" | ForEach-Object {
            [PSCustomObject]$Local:Formatted = Get-FormmatedUser $_;
            @{
                ADSI = $_;
                Formatted = "$($Local:Formatted.Domain)\$($Local:Formatted.Name)";
            };
        };
        while ($True) {
            [Int16]$Local:SelectedIndex = Get-UserSelection -Title 'Select User' 'Select the user you want to add to Network Configuration Operators:' -Choices $Local:Users.Formatted;
            [ADSI]$Local:User = $Local:Users[$Local:SelectedIndex];

            Add-MemberToGroup -Group $Local:Group -Username $Local:User.ADSI;
            $Local:Users.RemoveAt($Local:SelectedIndex);

            if (Get-UserConfirmation -Title 'Add another user?' -Question 'Do you want to add another user to Network Configuration Operators?' -Default $True) {
                continue;
            } else {
                break;
            }
        }
    }
};
