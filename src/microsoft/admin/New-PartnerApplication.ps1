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

Using module ../../common/Environment.psm1;

Param(
    [Parameter(Mandatory)]
    [string]$DisplayName,

    [Parameter()]
    [string]$TenantId
)

# Check if the Azure AD PowerShell module has already been loaded.
if ( ! ( Get-Module AzureAD ) ) {
    # Check if the Azure AD PowerShell module is installed.
    if ( Get-Module -ListAvailable -Name AzureAD ) {
        # The Azure AD PowerShell module is not load and it is installed. This module
        # must be loaded for other operations performed by this script.
        Write-Host -ForegroundColor Green 'Loading the Azure AD PowerShell module...'
        Import-Module AzureAD
    } else {
        Install-Module AzureAD
    }
}

try {
    Write-Host -ForegroundColor Green 'When prompted please enter the appropriate credentials... Warning: Window might have pop-under in VSCode'

    if ([string]::IsNullOrEmpty($TenantId)) {
        Connect-AzureAD | Out-Null

        $TenantId = $(Get-AzureADTenantDetail).ObjectId
    } else {
        Connect-AzureAD -TenantId $TenantId | Out-Null
    }
} catch [Microsoft.Azure.Common.Authentication.AadAuthenticationCanceledException] {
    # The authentication attempt was canceled by the end-user. Execution of the script should be halted.
    Write-Host -ForegroundColor Yellow 'The authentication attempt was canceled. Execution of the script will be halted...'
    Exit
} catch {
    # An unexpected error has occurred. The end-user should be notified so that the appropriate action can be taken.
    Write-Error 'An unexpected error has occurred. Please review the following error message and try again.' `
        "$($Error[0].Exception)"
}

$adAppAccess = [Microsoft.Open.AzureAD.Model.RequiredResourceAccess]@{
    ResourceAppId  = '00000002-0000-0000-c000-000000000000';
    ResourceAccess =
    [Microsoft.Open.AzureAD.Model.ResourceAccess]@{
        Id   = '5778995a-e1bf-45b8-affa-663a9f3f4d04';
        Type = 'Role'
    },
    [Microsoft.Open.AzureAD.Model.ResourceAccess]@{
        Id   = 'a42657d6-7f20-40e3-b6f0-cee03008a62a';
        Type = 'Scope'
    },
    [Microsoft.Open.AzureAD.Model.ResourceAccess]@{
        Id   = '311a71cc-e848-46a1-bdf8-97ff7156d8e6';
        Type = 'Scope'
    }
}

$graphAppAccess = [Microsoft.Open.AzureAD.Model.RequiredResourceAccess]@{
    ResourceAppId  = '00000003-0000-0000-c000-000000000000';
    ResourceAccess =
    [Microsoft.Open.AzureAD.Model.ResourceAccess]@{
        Id   = 'bf394140-e372-4bf9-a898-299cfc7564e5';
        Type = 'Role'
    },
    [Microsoft.Open.AzureAD.Model.ResourceAccess]@{
        Id   = '7ab1d382-f21e-4acd-a863-ba3e13f7da61';
        Type = 'Role'
    }
}

$partnerCenterAppAccess = [Microsoft.Open.AzureAD.Model.RequiredResourceAccess]@{
    ResourceAppId  = 'fa3d9a0c-3fb0-42cc-9193-47c7ecd2edbd';
    ResourceAccess =
    [Microsoft.Open.AzureAD.Model.ResourceAccess]@{
        Id   = '1cebfa2a-fb4d-419e-b5f9-839b4383e05a';
        Type = 'Scope'
    }
}

$SessionInfo = Get-AzureADCurrentSessionInfo

Write-Host -ForegroundColor Green 'Creating the Azure AD application and related resources...'

$app = New-AzureADApplication -AvailableToOtherTenants $true -DisplayName $DisplayName -IdentifierUris "https://$($SessionInfo.TenantDomain)/$((New-Guid).ToString())" -RequiredResourceAccess $adAppAccess, $graphAppAccess, $partnerCenterAppAccess -ReplyUrls @('urn:ietf:wg:oauth:2.0:oob', 'https://localhost', 'http://localhost', 'http://localhost:8400')
$password = New-AzureADApplicationPasswordCredential -ObjectId $app.ObjectId
$spn = New-AzureADServicePrincipal -AppId $app.AppId -DisplayName $DisplayName


$adminAgentsGroup = Get-AzureADGroup -Filter "DisplayName eq 'AdminAgents'"
Add-AzureADGroupMember -ObjectId $adminAgentsGroup.ObjectId -RefObjectId $spn.ObjectId

Write-Host 'Installing PartnerCenter Module.' -ForegroundColor Green
Install-Module PartnerCenter -Force -AllowClobber -Scope CurrentUser
Write-Host 'Sleeping for 30 seconds to allow app creation on O365' -ForegroundColor green
Start-Sleep 30
Write-Host 'Please approve General consent form.' -ForegroundColor Green
$PasswordToSecureString = $password.value | ConvertTo-SecureString -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($($app.AppId), $PasswordToSecureString)
$token = New-PartnerAccessToken -ApplicationId "$($app.AppId)" -Scopes 'https://api.partnercenter.microsoft.com/user_impersonation' -ServicePrincipal -Credential $credential -Tenant $($spn.AppOwnerTenantID) -UseAuthorizationCode
Write-Host 'Please approve Exchange consent form.' -ForegroundColor Green
$Exchangetoken = New-PartnerAccessToken -ApplicationId 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -Scopes 'https://outlook.office365.com/.default' -Tenant $($spn.AppOwnerTenantID) -UseDeviceAuthentication
Write-Host 'Please approve Azure consent form.' -ForegroundColor Green
$Azuretoken = New-PartnerAccessToken -ApplicationId "$($app.AppId)" -Scopes 'https://management.azure.com/user_impersonation' -ServicePrincipal -Credential $credential -Tenant $($spn.AppOwnerTenantID) -UseAuthorizationCode
Write-Host "Last initation required: Please browse to https://login.microsoftonline.com/$($spn.AppOwnerTenantID)/adminConsent?client_id=$($app.AppId)"
Write-Host 'Press any key after auth. An error report about incorrect URIs is expected!'
[void][System.Console]::ReadKey($true)
Write-Host '######### Secrets #########'
Write-Host "`$ApplicationId         = '$($app.AppId)'"
Write-Host "`$ApplicationSecret     = '$($password.Value)'"
Write-Host "`$TenantID              = '$($spn.AppOwnerTenantID)'"
Write-Host "`$RefreshToken          = '$($token.refreshtoken)'" -ForegroundColor Blue
Write-Host "`$ExchangeRefreshToken = '$($ExchangeToken.Refreshtoken)'" -ForegroundColor Green
Write-Host "`$AzureRefreshToken =   '$($Azuretoken.Refreshtoken)'" -ForegroundColor Magenta
Write-Host '######### Secrets #########'
Write-Host '    SAVE THESE IN A SECURE LOCATION     '
