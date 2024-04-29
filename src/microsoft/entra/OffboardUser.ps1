Using namespace Microsoft.Graph.PowerShell.Models;

function Update-Mailbox {
    param(
        [Parameter(Mandatory)]
        [MicrosoftGraphUser]$User
    )

    Set-MailBox -Identity:$User.Mail -Type:Shared -HiddenFromAddressListsEnabled:$True;
    
    # Forward and/or delegate the mailbox to another user
    # Set the mailbox to auto-reply if requested
}

function Update-User {
    # Revoke Sessions
    # Disable User
    # Change name to prefix with "zArchived - "
    # Remove from all groups
    # Remove all roles
    # Remove all licenses (This may need to be done after everything else)
}

Import-Module $PSScriptRoot/../../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    Invoke-EnsureModule "$PSScriptRoot/../Common.psm1", 'ExchangeOnlineManagement', 'Microsoft.Graph';
    Connect-Service 'Graph','ExchangeOnline' -Scopes @('User.ReadWrite.All', 'Directory.ReadWrite.All');

    # TODO :: Filter by licensed and enabled
    [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser[]]$Private:Users = Get-MgUser -Filter '';
    [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser]$Local:User = Get-UserSelection `
        -Title 'Which account?' `
        -Question 'Select the account you want to offboard/archive' `
        -Choices $Local:Users `
        -FormatChoice { param([Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser]$Item) $Item.UserPrincipalName };

    Update-Mailbox -User:$Local:User;
    Update-User -User:$Local:User;
};
