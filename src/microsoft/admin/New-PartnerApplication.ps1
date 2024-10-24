<#
.SYNOPSIS
    This script will create the required Azure AD application.

.EXAMPLE
    .\Create-AzureADApplication.ps1 -DisplayName "Partner Center Web App"

    .\Create-AzureADApplication.ps1 -DisplayName "Partner Center Web App" -TenantId eb210c1e-b697-4c06-b4e3-8b104c226b9a

    .\Create-AzureADApplication.ps1 -DisplayName "Partner Center Web App" -TenantId tenant01.onmicrosoft.com

.PARAMETER DisplayName
    Display name for the Azure AD application that will be created.

.PARAMETER TenantId
    [OPTIONAL] The domain or tenant identifier for the Azure AD tenant that should be utilized to create the various resources.

.NOTES
    This script was adapted from here: https://www.cyberdrain.com/using-the-secure-application-model-with-partnercenter-2-0-for-office365/
#>

#Requires -Version 5.1
#Requires -PSEdition Desktop

Using module ../../common/Analyser.psm1
Using module ../../common/Environment.psm1
Using module ../../common/Logging.psm1
Using module ../../common/Exit.psm1

Using module AzureAD
Using module PartnerCenter

Using namespace Microsoft.Open.AzureAD.Model

[CmdletBinding()]
Param(
    [Parameter(Mandatory)]
    [string]$DisplayName,

    [Parameter()]
    [string]$TenantId
)

try {
    if ([string]::IsNullOrEmpty($TenantId)) {
        Connect-AzureAD | Out-Null

        $TenantId = $(Get-AzureADTenantDetail).ObjectId
    } else {
        Connect-AzureAD -TenantId $TenantId | Out-Null
    }
} catch [Microsoft.Azure.Common.Authentication.AadAuthenticationCanceledException] {
    # The authentication attempt was canceled by the end-user. Execution of the script should be halted.
    Invoke-Warn 'The authentication attempt was canceled. Execution of the script will be halted...';
    Invoke-FailedExit -ExitCode 1 -ErrorRecord $_;
} catch {
    # An unexpected error has occurred. The end-user should be notified so that the appropriate action can be taken.
    Invoke-FailedExit -ExitCode 1 -ErrorRecord $_;
}

$adAppAccess = [RequiredResourceAccess]@{
    ResourceAppId  = '00000002-0000-0000-c000-000000000000';
    ResourceAccess =
    [ResourceAccess]@{
        Id   = '5778995a-e1bf-45b8-affa-663a9f3f4d04';
        Type = 'Role'
    },
    [ResourceAccess]@{
        Id   = 'a42657d6-7f20-40e3-b6f0-cee03008a62a';
        Type = 'Scope'
    },
    [ResourceAccess]@{
        Id   = '311a71cc-e848-46a1-bdf8-97ff7156d8e6';
        Type = 'Scope'
    }
}

$graphAppAccess = [RequiredResourceAccess]@{
    ResourceAppId  = '00000003-0000-0000-c000-000000000000';
    ResourceAccess =
    [ResourceAccess]@{
        Id   = 'bf394140-e372-4bf9-a898-299cfc7564e5';
        Type = 'Role'
    },
    [ResourceAccess]@{
        Id   = '7ab1d382-f21e-4acd-a863-ba3e13f7da61';
        Type = 'Role'
    }
}

$partnerCenterAppAccess = [RequiredResourceAccess]@{
    ResourceAppId  = 'fa3d9a0c-3fb0-42cc-9193-47c7ecd2edbd';
    ResourceAccess =
    [ResourceAccess]@{
        Id   = '1cebfa2a-fb4d-419e-b5f9-839b4383e05a';
        Type = 'Scope'
    }
}

$SessionInfo = Get-AzureADCurrentSessionInfo

Invoke-Info 'Creating the Azure AD application and related resources...';

$app = New-AzureADApplication -AvailableToOtherTenants $true -DisplayName $DisplayName -IdentifierUris "https://$($SessionInfo.TenantDomain)/$((New-Guid).ToString())" -RequiredResourceAccess $adAppAccess, $graphAppAccess, $partnerCenterAppAccess -ReplyUrls @('urn:ietf:wg:oauth:2.0:oob', 'https://localhost', 'http://localhost', 'http://localhost:8400')
$password = New-AzureADApplicationPasswordCredential -ObjectId $app.ObjectId
$spn = New-AzureADServicePrincipal -AppId $app.AppId -DisplayName $DisplayName

$adminAgentsGroup = Get-AzureADGroup -Filter "DisplayName eq 'AdminAgents'"
Add-AzureADGroupMember -ObjectId $adminAgentsGroup.ObjectId -RefObjectId $spn.ObjectId

Invoke-Info 'Sleeping for 30 seconds to allow app creation on O365'
Start-Sleep 30
Invoke-Info 'Please approve General consent form.'
$PasswordToSecureString = $password.value | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($($app.AppId), $PasswordToSecureString)
$token = New-PartnerAccessToken -ApplicationId "$($app.AppId)" -Scopes 'https://api.partnercenter.microsoft.com/user_impersonation' -ServicePrincipal -Credential $credential -Tenant $($spn.AppOwnerTenantID) -UseAuthorizationCode
Invoke-Info 'Please approve Exchange consent form.';
$Exchangetoken = New-PartnerAccessToken -ApplicationId 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -Scopes 'https://outlook.office365.com/.default' -Tenant $($spn.AppOwnerTenantID) -UseDeviceAuthentication
Invoke-Info 'Please approve Azure consent form.';
$Azuretoken = New-PartnerAccessToken -ApplicationId "$($app.AppId)" -Scopes 'https://management.azure.com/user_impersonation' -ServicePrincipal -Credential $credential -Tenant $($spn.AppOwnerTenantID) -UseAuthorizationCode
Invoke-Info "Last initation required: Please browse to https://login.microsoftonline.com/$($spn.AppOwnerTenantID)/adminConsent?client_id=$($app.AppId)"
Invoke-Info 'Press any key after auth. An error report about incorrect URIs is expected!'
[void][System.Console]::ReadKey($true);
Invoke-Info '######### Secrets #########';
Invoke-Info "`$ApplicationId         = '$($app.AppId)'";
Invoke-Info "`$ApplicationSecret     = '$($password.Value)'";
Invoke-Info "`$TenantID              = '$($spn.AppOwnerTenantID)'";
Invoke-Info "`$RefreshToken          = '$($token.refreshtoken)'";
Invoke-Info "`$ExchangeRefreshToken = '$($ExchangeToken.Refreshtoken)'";
Invoke-Info "`$AzureRefreshToken =   '$($Azuretoken.Refreshtoken)'";
Invoke-Info '######### Secrets #########';
Invoke-Info '    SAVE THESE IN A SECURE LOCATION     ';
