Using Module Microsoft.Graph.Authentication
Using Module Microsoft.Graph.Identity.DirectoryManagement
Using Module Microsoft.Graph.Users
Using Module ExchangeOnlineManagement

Using Module ..\common\Logging.psm1
Using Module ..\common\Scope.psm1
Using Module ..\common\Connection.psm1

Using namespace Microsoft.Graph.PowerShell.Models

Function Get-PrimaryDomain {
    Get-MgDomain | Where-Object { $_.IsDefault -eq $True };
}

function Get-AlertsUser {
    param(
        [Parameter()]
        [String]$SupportEmail = 'amtsupport@amt.com.au'
    )

    begin { Enter-Scope; Connect-Service -Services Graph,ExchangeOnline -Scopes 'User.ReadWrite.All','OrgContact.Read.All','Domain.Read.All'; }
    end { Exit-Scope -ReturnValue $Local:User; }

    process {
        Trap {
            Invoke-Warn @'
There was an error during the creation of the Alerts user.
If a new mailbox was created, please ensure that the user account is correctly disabled at the least.
'@;
            Write-Error -ErrorRecord $_;
            return $null;
        }
        $PSDefaultParameterValues['*:ErrorAction'] = 'Stop';

        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphDomain]$Local:Domain = Get-PrimaryDomain;
        [String]$Local:DomainName = $Domain.Id.Split('.')[0];
        [String]$Local:DisplayName = 'Alerts';
        [String]$Local:MailNickname = "alerts_$($DomainName)";
        [String]$Local:UserPrincipalName = "$Local:MailNickName@$($Local:Domain.Id)";

        #startregion Mailbox Setup
        [PSCustomObject]$Local:AlertsMailbox = Get-Mailbox -Filter "UserPrincipalName -eq '$($Local:UserPrincipalName)' -or UserPrincipalName -like 'alerts*'" -ErrorAction SilentlyContinue;
        if (-not $Local:AlertsMailbox) {
            Invoke-Info 'Creating mailbox for Alerts user...';
            New-Mailbox -Name 'Alerts' `
                -DisplayName $Local:DisplayName `
                -Alias $Local:MailNickname `
                -FirstName 'Alerts' `
                -LastName $Local:DomainName `
                -PrimarySmtpAddress $Local:UserPrincipalName `
                -Shared:$True | Out-Null;
        } else {
            Invoke-Info 'Alerts mailbox already exists.';
            $Local:UserPrincipalName = $Local:AlertsMailbox.UserPrincipalName;
        }

        if ((Get-Recipient -Identity $Local:UserPrincipalName).HiddenFromAddressListsEnabled -ne $True) {
            Invoke-Info 'Hiding mailbox from address lists...';
            Set-Mailbox -Identity $Local:UserPrincipalName -HiddenFromAddressListsEnabled:$True;
        }

        do {
            [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser]$Local:User = Get-MgUser -Property Id, AccountEnabled -Filter "UserPrincipalName eq '$($Local:UserPrincipalName)'";

            if (-not $Local:User) {
                Invoke-Verbose 'Waiting for user to be created...';
                Start-Sleep -Seconds 5;
                continue;
            }
        } while ($null -eq $Local:User)

        if ($Local:User.AccountEnabled -ne $False) {
            Invoke-Info "Disabling account $($Local:UserPrincipalName)...";
            Update-MgUser -UserId $Local:User.Id -AccountEnabled:$False;
        }

        if (-not (Get-Mailbox -Filter "UserPrincipalName -eq '$($Local:UserPrincipalName)'" -RecipientTypeDetails SharedMailbox -ErrorAction SilentlyContinue)) {
            Invoke-Info "Converting Mailbox $($Local:UserPrincipalName) to shared...";
            Set-Mailbox -Identity $Local:UserPrincipalName -Type Shared | Out-Null;
        }

        #startregion Admin Delegate Access
        $Local:Admin = Get-MgUser -Filter "startswith(UserPrincipalName, 'admin@') or startswith(UserPrincipalName, 'amtadmin@') or startsWith(UserPrincipalName, 'O365Admin@')";
        if (-not $Local:Admin) {
            Invoke-Warn 'Could not find admin account, please select the admin account to grant delegate access to the Alerts mailbox.';
            [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser[]]$Local:AllUsers = Get-MgUser;
            [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser]$Local:Admin = Get-UserSelection `
                -Title 'Which account?' `
                -Question 'Select the admin account to grant delegate access to the Alerts mailbox' `
                -Choices $Local:AllUsers `
                -FormatChoice { param([Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser]$Item) $Item.UserPrincipalName };
        } elseif ($Local:Admin.Count -gt 1) {
            Invoke-Warn 'Multiple admin accounts found, please select the admin account to grant delegate access to the Alerts mailbox.';
            [Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser]$Local:Admin = Get-UserSelection `
                -Title 'Which account?' `
                -Question 'Select the admin account to grant delegate access to the Alerts mailbox' `
                -Choices $Local:Admin `
                -FormatChoice { param([Microsoft.Graph.PowerShell.Models.MicrosoftGraphUser]$Item) $Item.UserPrincipalName };
        }

        [PSObject]$Local:ExistingPermission = Get-MailboxPermission -Identity $Local:UserPrincipalName -User $Local:Admin.UserPrincipalName -ErrorAction SilentlyContinue;
        if (-not $Local:ExistingPermission -or -not ($Local:ExistingPermission.AccessRights -eq 'FullAccess')) {
            Invoke-Info "Granting delegate access to $($Local:Admin.UserPrincipalName) for $($Local:UserPrincipalName)...";
            Add-MailboxPermission -Identity $Local:UserPrincipalName -User $Local:Admin.UserPrincipalName -AccessRights FullAccess | Out-Null;
        } else {
            Invoke-Info "Delegate access already granted to $($Local:Admin.UserPrincipalName) for $($Local:UserPrincipalName).";
        }
        #endregion

        #startregion AMT Support Contact
        [String]$Local:ContactName = 'AMT Support';

        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphContact]$Local:Contact = Get-MgContact -Filter "DisplayName eq '$Local:ContactName'";
        if (-not $Local:Contact) {
            Invoke-Info "Creating $Local:ContactName contact...";
            New-MailContact `
                -Name $Local:ContactName `
                -DisplayName $Local:ContactName `
                -ExternalEmailAddress $SupportEmail | Out-Null;
        } else {
            Invoke-Info "$Local:ContactName contact already exists.";
        }

        do {
            [Microsoft.Graph.PowerShell.Models.MicrosoftGraphContact]$Local:Contact = Get-MgContact -Filter "DisplayName eq 'AMT Support'";

            if (-not $Local:Contact) {
                Invoke-Verbose 'Waiting for contact to be created...';
                Start-Sleep -Seconds 5;
                continue;
            }
        } while ($null -eq $Local:Contact)
        #endregion

        #startregion Forwarding
        [String]$Local:PolicyName = 'Allow Outbound Forwarding';

        $Local:Mailbox = Get-Mailbox -Identity $Local:UserPrincipalName;
        if ($Local:Mailbox.ForwardingAddress -eq $Local:ContactName -and $Local:Mailbox.DeliverToMailboxAndForward -eq $True) {
            Invoke-Info 'Forwarding is already set up.';
        } else {
            Invoke-Info 'Setting up forwarding...';
            $Local:Mailbox | Set-Mailbox `
                -ForwardingAddress $SupportEmail `
                -DeliverToMailboxAndForward $True;
        }

        if (Get-OrganizationConfig | Select-Object -ExpandProperty IsDehydrated) {
            Invoke-Info 'Enabling organization customization...';
            try {
                Enable-OrganizationCustomization;
            } catch {
                Invoke-Verbose 'Organization customization is already enabled.';
            }
        }

        do {
            [Bool]$Local:IsDehydrated = (Get-OrganizationConfig).IsDehydrated;

            if ($Local:IsDehydrated) {
                if ($Local:ShownDehydrationWarning -ne $True) {
                    Invoke-Warn 'Organization customization is not yet complete, this may take up to 30 minutes...';
                    $Local:ShownDehydrationWarning = $True;
                }

                Invoke-Verbose 'Waiting for organization customization to complete...';
                Start-Sleep -Seconds 5;
                continue;
            }
        } while ($Local:IsDehydrated -eq $True)

        $Local:ExistingPolicy = Get-HostedOutboundSpamFilterPolicy -Identity $Local:PolicyName -ErrorAction SilentlyContinue;
        if (-not $Local:ExistingPolicy) {
            $Local:ExistingPolicy = Get-HostedOutboundSpamFilterPolicy -Identity 'Allow AMT Support' -ErrorAction SilentlyContinue;
        }

        if (-not $Local:ExistingPolicy) {
            Invoke-Info 'Creating Outbound Forwarding policy...';

            # Create the rule so we can update it later
            $Local:ExistingPolicy = New-HostedOutboundSpamFilterPolicy -Name $Local:PolicyName;
        } else {
            Invoke-Info 'Outbound Forwarding policy already exists.';
            $Local:PolicyName = $Local:ExistingPolicy.Name;
        }

        if ($Local:ExistingPolicy.AutoForwardingMode -ne 'On') {
            Invoke-Info 'Enabling Auto Forwarding...';
            Set-HostedOutboundSpamFilterPolicy -Identity $Local:PolicyName -AutoForwardingMode:'On' | Out-Null;
        } else {
            Invoke-Info 'Auto Forwarding is already enabled.';
        }

        $Local:ExistingRule = Get-HostedOutboundSpamFilterRule -Identity $Local:PolicyName -ErrorAction SilentlyContinue;
        if (-not $Local:ExistingRule) {
            New-HostedOutboundSpamFilterRule `
                -Name $Local:PolicyName `
                -From $Local:UserPrincipalName `
                -HostedOutboundSpamFilterPolicy $Local:PolicyName | Out-Null;
        } else {
            [HashTable]$Local:SetParams = @{ Identity = $Local:PolicyName; };
            if ($Local:ExistingRule.From -ne $Local:UserPrincipalName) {
                $Local:SetParams.Add('From', $Local:UserPrincipalName);
            }
            if ($Local:ExistingRule.HostedOutboundSpamFilterPolicy -ne $Local:PolicyName) {
                $Local:SetParams.Add('HostedOutboundSpamFilterPolicy', $Local:PolicyName);
            }

            if ($Local:SetParams.Count -gt 1) {
                Invoke-Info 'Updating Outbound Forwarding rule...';
                Set-HostedOutboundSpamFilterRule @Local:SetParams;
            } else {
                Invoke-Info 'Outbound Forwarding rule is up to date.';
            }
        }
        #endregion

        return $Local:UserPrincipalName;
    }
}

<#
.SYNOPSIS
    Iterate through every customers tenant and invoke a script block

.DESCRIPTION
    This function will iterate through every customer tenant and invoke a script block with the tenant as the current scope.
    This is useful for running scripts that need to be run for every customer.

.PARAMETER ScriptBlock
    The script block to invoke for each customer tenant.

.EXAMPLE
    Invoke-ForEachCustomer {
        Get-AlertsUser;
    }

.NOTES
    This is a very powerful function and should be used with caution.
#>
function Invoke-ForEachCustomer {
    param(
        [Parameter(Mandatory)]
        [ScriptBlock]$ScriptBlock,

        [Parameter()]
        [String]$VaultName = 'DelegatedAccessTokens'
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        Invoke-EnsureModule 'PartnerCenter','Az.Accounts','Az.KeyVault';

        Invoke-Info 'Please sign in with the Azure AD account that has access to the Delegated Access Tokens...';
        Connect-AzAccount -UseDeviceAuthentication;

        Invoke-Info 'Getting Delegated Access Tokens...';
        [String]$Private:AppilicationID = Get-AzKeyVaultSecret -VaultName $VaultName -Name 'ApplicationID' -AsPlainText;
        [SecureString]$Private:ApplicationSecret = Get-AzKeyVaultSecret -VaultName $VaultName -Name 'ApplicationSecret';
        [SecureString]$Private:RefreshToken = Get-AzKeyVaultSecret -VaultName $VaultName -Name 'RefreshToken';
        # [SecureString]$Private:ExchangeRefreshToken = Get-AzKeyVaultSecret -VaultName $VaultName -Name 'ExchangeRefreshToken';
        # [SecureString]$Private:AzureRefreshToken = Get-AzKeyVaultSecret -VaultName $VaultName -Name 'AzureRefreshToken';

        Invoke-Info 'Getting Partner Center token...'
        [System.Management.Automation.PSCredential]$Private:Credential = New-Object System.Management.Automation.PSCredential -ArgumentList $Private:AppilicationID, $Private:ApplicationSecret;
        $Private:GraphToken = Get-PartnerAccessToken -ApplicationId $Private:AppilicationID -Credential $Private:Credential -RefreshToken $Private:RefreshToken -Scopes 'https://graph.microsoft.com/.default' -ServicePrincipal;

        Invoke-Info 'Getting Partner Center customers...';
        Connect-MgGraph -AccessToken $Private:GraphToken.AccessToken -NoWelcome;
        $Private:Customers = Get-MgContract -All;
        Disconnect-MgGraph;

        foreach ($Private:Customer in $Private:Customers) {
            Invoke-Info 'Getting customer token...';
            $Private:GraphToken = Get-PartnerAccessToken -ApplicationId $Private:AppilicationID -Credential $Private:Credential -RefreshToken $Private:RefreshToken -Scopes 'https://management.azure.com' -ServicePrincipal -TenantId $Private:Customer.TenantId;
            Invoke-Info 'Connecting to services...';
            Connect-MgGraph -AccessToken $Private:GraphToken.AccessToken -NoWelcome;
            Connect-ExchangeOnline -AccessToken $Private:GraphToken.AccessToken -NoWelcome;

            Invoke-Info 'Invoking script block...';
            Invoke-Command -ScriptBlock $ScriptBlock;

            Invoke-Info 'Disconnecting from services...';
            Disconnect-MgGraph;
            Disconnect-ExchangeOnline;
        }
    }
}

Export-ModuleMember -Function Get-AlertsUser, Invoke-ForEachCustomer;
