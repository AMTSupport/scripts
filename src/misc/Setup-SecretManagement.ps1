#Requires -Version 7.4

Using module ../common/Environment.psm1
Using module ../common/Ensure.psm1
Using module ../common/Input.psm1

Using module Microsoft.Powershell.SecretManagement

[CmdletBinding()]
param()

function Install-1Password {
    if (Get-Command -Name 'op' -ErrorAction SilentlyContinue) {
        return;
    }

    # We use winget here because we can't run chocolatey in a non-administrator shell.
    winget install -e -h --scope user --accept-package-agreements --accept-source-agreements --id AgileBits.1Password.CLI;
    [String]$Local:EnvPath = $env:LOCALAPPDATA | Join-Path -Child 'Microsoft\WinGet\Links';

    if ($env:PATH -notlike "*$Local:EnvPath*") {
        $env:PATH += ";$Local:EnvPath";
    }

}

Invoke-RunMain $PSCmdlet {
    Invoke-EnsureUser;
    Install-ModuleFromGitHub -GitHubRepo 'cdhunt/SecretManagement.1Password' -Branch 'vNext' -Scope CurrentUser;
    Install-1Password;

    if ((Get-SecretVault -Name 'PowerShell Secrets' -ErrorAction SilentlyContinue)) {
        [Boolean]$Local:Response = Get-UserConfirmation `
            -Title 'Recreate Secret Vault' `
            -Question 'Secret vault already exists; do you want to recreate it?';

        if ($Local:Response) {
            Remove-SecretVault -Name 'PowerShell Secrets';
        } else {
            return;
        }
    }

    [Boolean]$Local:Email = Get-UserInput `
        -Title '1Password Email' `
        -Question 'Enter your 1Password email address' `
        -Validate {
            param([String]$UserInput);

            $UserInput -match $Validations.Email;
        };

    [String]$Local:SecretKey = Get-UserInput `
        -AsSecureString `
        -Title '1Password Secret Key' `
        -Question 'Enter your 1Password secret key' `
        -Validate {
            param([String]$UserInput);

            $UserInput -match '^A3(?:-[A-Z0-9]{5,6}){6}$';
        }

    [HashTable]$Local:SecretVault = @{
        Name            = 'PowerShell Secrets';
        ModuleName      = 'SecretManagement.1Password';
        VaultParameters = @{
            AccountName     = 'teamamt';
            EmailAddress    = $Local:Email;
            SecretKey       = $Local:SecretKey;
        };
    };

    Register-SecretVault @Local:SecretVault;
};
