Import-Module $PSScriptRoot/../../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    Connect-Service Graph -Scopes Device.ReadWrite.All, DeviceManagementManagedDevices.ReadWrite.All, DeviceManagementServiceConfig.ReadWrite.All, Group.ReadWrite.All, GroupMember.ReadWrite.All, Mail.ReadWrite.Shared, openid, profile, User.ReadWrite.All, email, Directory.Read.All, LicenseAssignment.ReadWrite.All;

    # TODO :: Filter only licensed users.
    [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser[]]$Local:Users = Get-MgUser;
    [String]$Local:UserSelection = Get-PopupSelection -Title 'Select the user to offboard.' -Items $Local:Users.Name;
    [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser]$Local:User = $Local:Users | Where-Object { $_.Mail -eq $Local:UserSelection } | Select-Object -First 1;

    if (-not (Get-Confirmation -Message "Are you sure you want to offboard $($Local:User.Name)/$($Local:User.Mail)?")) {
        return;
    }

    # Revoke Sign-In Sessions for the user.
    # Disable the account
    # Change the name to "zArchived - <Original Name>"
    # Remove the user from all security groups.
    # Remove the user from all teams.
    # Remove the user from all sharepoint libraries.
    # Remove the user from all distribution groups.
    # Remove the users licenses.

    # Hide from the GAL.
    # Convert to shared mailbox.
    Set-MailBox -Identity $User.Mail -Type Shared; # TODO :: Graph API

    # Archive the user's mailbox and set the mailbox to a shared mailbox.
    # Select a user to give delegated access to the mailbox.
    # Add the user to the mailbox.

    # Select a user to give delegated access to the OneDrive.
    # Add the user to the OneDrive.
};
