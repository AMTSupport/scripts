Using module ../../common/Environment.psm1
Using module ../../common/Connection.psm1
Using module ../../common/Input.psm1

Using module Microsoft.Graph.Identity.DirectoryManagement

function Get-RandomPassword {
    # Generate a random password using RPGen
}

function Save-ToHudu {
    # Get Company
}

function New-User {
    # Determine what licenses are required by prompting the user,
    # Use a auto complete input box to allow the user to select the licenses
}

Invoke-RunMain $PSCmdlet {
    Connect-Service -Services @('Graph') -Scopes @('User.ReadWrite.All', 'Directory.ReadWrite.All');

    #region - Get user details

    $Private:ValidDomains = Get-MgDomain;

    # TODO :: Is Validation required?
    $Private:UserDetails = @{
        Name        = @{
            FirstName = Get-UserInput 'First Name' 'What is the first name of the user?';
            LastName  = Get-UserInput 'Last Name' 'What is the last name of the user?';
        };

        PhoneNumber = Get-UserInput 'Phone Number' 'What is the phone number of the user?' -AllowEmpty;

        Email       = @{
            Name   = Get-UserInput 'Email Address' 'What is the email address of the user?';
            Domain = Get-UserSelection
        };
    };

    $Private:Licenses = @{
        Business = @('Basic', 'Standard', 'Premium')
        Defender = @('Office', 'Cloud')
    };
    #endregion
};
