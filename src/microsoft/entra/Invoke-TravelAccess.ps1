param(
    [Parameter(Mandatory)]
    [ValidateSet('Grant', 'Revoke', 'Check')]
    [String]$Action
)

function Get-TravelGroup {
    # If there is a staff group such as Staff UK, add that
    # Otherwise only get the travel group
}

function Add-TravelAccess {

}

function Remove-TravelAccess {
    # Remove group from user

}

function Test-TravelAccess {
    # Try to use graph api to use whatif with a generated ip from country-ip
}

Import-Module $PSScriptRoot/../../common/Environment.psm1;
Invoke-RunMain $PSCmdlet {
    # Get exact users by recursive input quary

    switch ($Action) {
        'Grant' {
            $users = Invoke-GetUsers -Query "Department -eq 'Travel'";
            $users | ForEach-Object {
                Invoke-GrantAccess -User $_ -Resource 'Travel';
            }
        }
        'Revoke' {
            $users = Invoke-GetUsers -Query "Department -eq 'Travel'";
            $users | ForEach-Object {
                Invoke-RevokeAccess -User $_ -Resource 'Travel';
            }
        }
        'Check' {
            $users = Invoke-GetUsers -Query "Department -eq 'Travel'";
            $users | ForEach-Object {
                Invoke-CheckAccess -User $_ -Resource 'Travel';
            }
        }
    }
};
