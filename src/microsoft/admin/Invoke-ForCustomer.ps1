Using module Microsoft.Graph.Authentication;
Using module PartnerCenter;

Using module ../../common/Environment.psm1;

[CmdletBinding(DefaultParameterSetName = 'ScriptBlock')]
param (
    [Parameter(
        Mandatory,
        ParameterSetName = 'ScriptBlock',
        HelpMessage = 'The script block to execute for each customer.')]
    [ScriptBlock]$ScriptBlock,

    [Parameter(
        Mandatory,
        ParameterSetName = 'ScriptFile',
        HelpMessage = 'The script file to execute for each customer.')]
    [Alias('PSPath')]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path $_ -PathType Leaf -and $_ -match '\.ps1$' })]
    [String]$ScriptFile,

    [Parameter(
        ParameterSetName = 'ScriptFile',
        HelpMessage = 'Extra parameters to pass to the script file.')]
    [Alias('Args')]
    [Hashtable]$Parameters,

    # [Parameter(HelpMessage = 'Preserve the access tokens for each customer tenant, for future use.')]
    [Parameter(ParameterSetName = 'ScriptBlock')]
    [Parameter(ParameterSetName = 'ScriptFile')]
    [Switch]$PreserveTokens
);

$Script:ConsentScope = 'https://api.partnercenter.microsoft.com/user_impersonation';
$Script:AppDisplayName = 'Partner Portal Delegated Tenant Access';

Function Invoke-ConsentForCustomer {
    <#
    .SYNOPSIS
        Grants consent to the specified customer tenant for the specified CSP application.

    .DESCRIPTION
        This function grants consent to the specified customer tenant for the specified CSP application by creating application grants for Microsoft Graph and Azure Resource Manager (ARM) APIs.

    .PARAMETER AccessToken
        The access token to connect to Partner Center.

    .PARAMETER CustomerTenantId
        The Tenant ID of the customer account for which consent is being granted.

    .EXAMPLE
        Invoke-ConsentForCustomer -AccessToken $AccessToken -CustomerTenantId $CustomerTenantId

        Grants consent to the specified customer tenant for the specified CSP application.
    #>
    Param(
        [Parameter(Mandatory)]
        [String]$AccessToken,

        [Parameter(Mandatory)]
        [String]$CustomerTenantId
    )

    Connect-PartnerCenter -AccessToken $AccessToken | Out-Null;

    $Private:MSGraphGrant = [Microsoft.Store.PartnerCenter.Models.ApplicationConsents.ApplicationGrant]@{
        EnterpriseApplicationId = '00000003-0000-0000-c000-000000000000' # List of application Ids is on https://learn.microsoft.com/en-us/troubleshoot/azure/active-directory/verify-first-party-apps-sign-in
        Scope                   = @(
            'Application.Read.All',
            'Device.Read.All',
            'Directory.Read.All',
            'Domain.Read.All',
            'Group.ReadWrite.All',
            'GroupMember.ReadWrite.All',
            'Organization.Read.All',
            'OrgContact.Read.All',
            'Policy.Read.All',
            'SecurityEvents.Read.All',
            'User.Export.All',
            'User.ReadWrite.All'
        );
    };

    $Private:ARMGrant = [Microsoft.Store.PartnerCenter.Models.ApplicationConsents.ApplicationGrant]@{
        EnterpriseApplicationId = '797f4846-ba00-4fd7-ba43-dac1f8f63013' # List of application Ids is on https://learn.microsoft.com/en-us/troubleshoot/azure/active-directory/verify-first-party-apps-sign-in
        Scope                   = 'user_impersonation';
    };

    Invoke-Info @"
Customer Tenant ID: $CustomerTenantId
Application ID: $Script:AppId
Application Display Name: $Script:AppDisplayName
Application Grants:
    - Microsoft Graph: $($Private:MSGraphGrant.Scope -join ', ')
    - Azure Resource Manager: $($Private:ARMGrant.Scope)
"@;

    New-PartnerCustomerApplicationConsent `
        -ApplicationGrants @($Private:ARMGrant, $Private:MSGraphgrant) `
        -CustomerId $CustomerTenantId `
        -ApplicationId $Script:AppId `
        -DisplayName $Script:AppDisplayName;
}

Function Invoke-ConsentPartnerApplication {
    <#
    .SYNOPSIS
        Grants consent for a partner application to access customer resources.
    .DESCRIPTION
        This function grants consent for a partner application to access customer resources. It first retrieves the partner access token using the Get-AuthenticationTokens function, and then calls the Invoke-ConsentForCustomer function to grant consent for the specified CSP application.
    .EXAMPLE
        Invoke-ConsentPartnerApplication
        This example grants consent for the MgGraphMultiTenant CSP application to access customer resources.
    #>
    param(
        [Parameter(Mandatory)]
        [String]$CustomerTenantId
    )

    $Private:PartnerAccessToken = Get-AuthenticationTokens -TokenType:Partner -CustomerTenantId:$CustomerTenantId;
    Invoke-ConsentForCustomer -AccessToken:$Private:PartnerAccessToken.AccessToken -CustomerTenantId:$CustomerTenantId;
}

# Not sure if this is needed?
function Set-AuthHeaders {
    <#
    .SYNOPSIS
    Sets the authentication headers for a REST API request.

    .DESCRIPTION
    This function sets the authentication headers for a REST API request. It takes an access token and an expiration date as parameters and creates a hashtable with the necessary headers.

    .PARAMETER AccessToken
    The access token to be used for authentication.

    .PARAMETER ExpiresOn
    The expiration date of the access token.

    .EXAMPLE
    Set-AuthHeaders -AccessToken $AccessToken.AccessToken -ExpiresOn $AccessToken.ExpiresOn
    #>
    Param (
        [Parameter(Mandatory)]
        [String]$AccessToken,

        [Parameter(Mandatory)]
        [String]$ExpiresOn
    )

    $Script:AuthHeader = @{
        'Content-Type'  = 'application/json'
        'Authorization' = 'Bearer ' + $AccessToken
        'ExpiresOn'     = $ExpiresOn
    }
}

function Get-AuthenticationTokens {
    <#
    .SYNOPSIS
        This function retrieves authentication tokens for Partner Center API and Microsoft Graph API.

    .DESCRIPTION
        This function retrieves authentication tokens for Partner Center API and Microsoft Graph API based on the provided parameters.
        It uses the New-PartnerAccessToken cmdlet to retrieve the access tokens.

    .PARAMETER TokenType
        Specifies the type of token to retrieve. Valid values are "Partner" and "Customer".

    .PARAMETER CustomerTenantId
        Specifies the Tenant ID of the customer account. This parameter is required only if TokenType is "Customer".

    .EXAMPLE
        PS C:\> Get-AuthenticationTokens -TokenType Customer -CustomerTenantId "87654321-4321-4321-4321-210987654321"
        Retrieves Customer Access Token for the specified CSP app and customer account.
    #>
    param (
        [String]$TokenType,

        [String]$CustomerTenantId
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue:$Local:AccessToken; }

    process {
        if ($TokenType -eq 'Customer' -and $Script:AccessTokens.ContainsKey($CustomerTenantId)) {
            Invoke-Debug 'Access token already exists for the customer tenant.';
            $Local:AccessToken = $Script:AccessTokens[$CustomerTenantId];
            # TODO Check if the access token is still valid
            return $Local:AccessToken;
        }

        $Local:PartnerAccessToken = $null;
        Invoke-Info 'Retrieving Partner Access Token...';
        if ($Script:AccessTokens.ContainsKey('PartnerAccessToken')) {
            $Local:PartnerAccessToken = $Script:AccessTokens['PartnerAccessToken'];
            # TODO Check if the access token is still valid
            # if ($Local:AccessToken.ExpiresOn -gt (Get-Date)) {
            #     Invoke-Info 'Partner Access Token is not longer valid.';
            #     $Script:AccessTokens.Remove('PartnerAccessToken');
            #     $Local:AccessToken = $null;
            # }
        }

        if ($null -eq $Local:PartnerAccessToken) {
            $Script:AccessTokens['PartnerAccessToken'] = $Local:PartnerAccessToken = New-PartnerAccessToken `
                -ServicePrincipal `
                -ApplicationId:$Script:AppId `
                -Credential:$Script:AppCredential `
                -Scopes:$Script:ConsentScope `
                -Tenant:$Script:PartnerTenantid `
                -UseAuthorizationCode;
            Invoke-Info 'Partner Access Token has been successfully retrieved.';
        }

        if ($TokenType -eq 'Customer') {
            Invoke-Info 'Retrieving Customer Access Token...';
            $Script:AccessTokens[$CustomerTenantId] = $Local:AccessToken = New-PartnerAccessToken `
                -ApplicationId:$Script:AppId `
                -Credential:$Script:AppCredential `
                -Scopes:'https://graph.microsoft.com/.default' `
                -ServicePrincipal `
                -Tenant:$CustomerTenantId `
                -RefreshToken $Local:PartnerAccessToken.RefreshToken;
            Invoke-Info 'Customer Access Token has been successfully retrieved.';

            return $Local:AccessToken;
        }
        else {
            return $Local:PartnerAccessToken;
        }
    }
}

function Invoke-InCustomerContext {
    param(
        [Parameter(Mandatory)]
        [String]$CustomerTenantId
    )

    begin {
        Enter-Scope;

        # Getting access token for the customer tenant
        Invoke-Info "Retrieving access token for $CustomerTenantId's tenant...";
        do {
            $Local:AccessToken = Get-AuthenticationTokens -TokenType:Customer -CustomerTenantId:$CustomerTenantID;
            Invoke-Debug "Retrieved access token: $($Local:AccessToken.AccessToken)";

            if ($null -eq $Local:AccessToken) {
                Invoke-Info "Consenting Azure AD App on $CustomerTenantId's tenant...";
                Invoke-ConsentPartnerApplication -CustomerTenantId $CustomerTenantID;
                Invoke-Info "Successfully consented Azure AD App on $CustomerTenantId's tenant.";
                Invoke-Info "Attempting to connect to $CustomerTenantId's tenant again...";
            }
        } while ($null -eq $Local:AccessToken)
        [SecureString]$Local:SecureAccessToken = ConvertTo-SecureString -String $Local:AccessToken.AccessToken -AsPlainText -Force;
        Invoke-Info "Successfully retrieved access token for $CustomerTenantId's tenant.";

        Invoke-Info "Setting Auth Headers for $CustomerTenantId's tenant...";
        Set-AuthHeaders -AccessToken $Local:AccessToken.AccessToken -ExpiresOn $Local:AccessToken.ExpiresOn;
        Invoke-Info "Successfully set Auth Headers for $CustomerTenantId's tenant.";

        # Connecting to the customer tenant using the access token retrieved in the previous step
        Invoke-Info "Connecting to $CustomerTenantId's M365 tenant through Microsoft Graph API...";
        Connect-MgGraph -AccessToken:$Local:SecureAccessToken | Out-Null;
        Invoke-Info "Successfully connected to $CustomerTenantId's M365 tenant through Microsoft Graph API.";
    };

    process {
        Invoke-Info "Executing script in the context of $CustomerTenantId's tenant...";
        if ($ScriptBlock) {
            Invoke-Command -ScriptBlock $ScriptBlock;
        }
        elseif ($ScriptFile) {
            Invoke-Expression -Command $ScriptFile @Parameters;
        }
        Invoke-Info "Script execution completed in the context of $CustomerTenantId's tenant.";
    };

    end {
        Exit-Scope;
        Disconnect-MgGraph | Out-Null;
        Remove-Variable -Name AuthHeader -Scope Script;
    };
}

# TODO - Multiple selection
# TODO - Quick select all
function Select-Customer {
    <#
    .SYNOPSIS
        This function allows the user to select a customer and connect to their M365 tenant and Azure AD.
    .DESCRIPTION
        This function retrieves a list of customers and their corresponding Tenant IDs, prompts the user to select a customer, and then connects to the selected customer's M365 tenant and Azure AD. It also retrieves an access token for the selected customer's tenant and sets the authentication headers for the Microsoft Graph API.
    .PARAMETER None
        This function does not accept any parameters.
    .EXAMPLE
        PS C:\> Select-Customer
        This example shows how to use the Select-Customer function to select a customer and connect to their M365 tenant and Azure AD.
    .INPUTS
        None. You cannot pipe objects to Select-Customer.
    .OUTPUTS
        Returns an access token for the selected customer's tenant.
    #>
    $Local:ExistingToken = $Script:AccessTokens['PartnerAccessToken'];
    if (-not [string]::IsNullOrWhiteSpace($Local:ExistingToken.AccessToken)) {
        [SecureString]$Local:SecureToken = ConvertTo-SecureString -String $Local:ExistingToken.AccessToken -AsPlainText -Force;
        Connect-Service 'Graph' -Scopes 'Directory.Read.All' -AccessToken:$Local:SecureToken;
    }
    else { Connect-Service 'Graph' -Scopes 'Directory.Read.All'; }

    [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphContract[]]$Customers = Get-MgContract -All;
    return Get-UserSelection `
        -Title 'Select Customer' `
        -Question 'Please select the customer you want to connect to' `
        -Choices $Customers `
        -DefaultChoice $null `
        -FormatChoice { param($Customer) "$($Customer.DisplayName)"; };
}

$Script:Cmdlet = $PSCmdlet;
Invoke-RunMain $PSCmdlet -NotStrict -Main {
    [String]$Script:AppId = Get-VarOrSave 'MULTITENANT_APP_ID' { Get-UserInput -Title 'Application ID' -Prompt 'Please enter the Application ID of the CSP application.' };
    [String]$Script:AppSecret = Get-VarOrSave 'MULTITENANT_APP_SECRET' { Get-UserInput -Title 'Application Secret' -Prompt 'Please enter the Application Secret of the CSP application.' };
    [String]$Script:PartnerTenantid = Get-VarOrSave 'MULTITENANT_PARTNER_ID' { Get-UserInput -Title 'Partner Tenant ID' -Prompt 'Please enter the Tenant ID of the Partner Center account.' };
    [PSCredential]$Script:AppCredential = [System.Management.Automation.PSCredential]::new(
        $Script:AppId,
        (ConvertTo-SecureString $Script:AppSecret -AsPlainText -Force)
    );

    if ($PreserveTokens) {
        $Script:AccessTokens = (Get-VarOrSave 'MULTITENANT_ACCESS_TOKENS' { '{}' }) | ConvertFrom-Json -Depth 5 -AsHashtable;
    }

    $Private:Customer = Select-Customer;
    try {
        Invoke-InCustomerContext -CustomerTenantId:($Private:Customer.CustomerId);
    }
    catch {
        Invoke-FailedExit -ExitCode 999 -ErrorRecord $_;
    }
    finally {
        if ($PreserveTokens) {
            [Environment]::SetEnvironmentVariable('MULTITENANT_ACCESS_TOKENS', ($Script:AccessTokens | ConvertTo-Json -Depth 5));
        }
    }
};

