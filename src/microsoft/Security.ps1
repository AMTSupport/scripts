Using module ..\common\Environment.psm1
Using module ..\common\Connection.psm1
Using module .\Common.psm1

Using module Microsoft.Online.SharePoint.PowerShell
Using module AzureAD
Using module ExchangeOnlineManagement

[CmdletBinding()]
Param(
    [Parameter(Mandatory)]
    [ValidateSet('SecurityAlerts', 'ConditionalAccess', 'Sharepoint', 'Exchange')]
    [String]$Action
)

#region - OneDrive & Sharepoint

function Set-Sharepoint_SharingDomains {
    Connect-Service -Service AzureAD;

    Set-SPOTenant -SharingDomainRestrictionMode AllowList -SharingAllowedDomainList ((Get-AzureADDomain | Select-Object -ExpandProperty Name) -join ' ')
}

#region - Exchange Mailbox Policies

function Disable-Outlook_StorageProviders {
    Connect-Service -Service ExchangeOnline;

    Set-OwaMailboxPolicy -Identity OwaMailboxPolicy-Default -AdditionalStorageProvidersAvailable $false
}

#endregion - Exchange Mailbox Policies

#region - Alerts and Notifications

function Set-SecurityAndCompilenceAlerts([PSObject]$AlertsUser) {
    $Alerts = Get-ProtectionAlert
    $AlertNames = $Alerts | Select-Object -ExpandProperty Name
    $Alerts = $Alerts | Where-Object { ($_.NotifyUser -ne $AlertsUser.WindowsLiveID) -and !$_.Disabled }

    if ($null -eq $Alerts -or $Alerts.Count -eq 0) {
        Write-Host 'All Security and Complience alerts are already configured to notify the Alerts user.'
        return
    }

    $UnableToCreate = @()
    foreach ($Alert in $Alerts) {
        if ($Alert.IsSystemRule) {
            # Check for existing custom rule
            if ($AlertNames -contains "AMT $($Alert.Name)") {
                Write-Host "Custom alert already exists for $($Alert.Name). Skipping..."
                continue
            }

            # We need to re-create this as a custom rule so we can modify the NotifyUser property
            $NewAlert = $Alert | Select-Object -Property * | ForEach-Object {
                $_.Name = "AMT $($_.Name)"
                $_.NotifyUser = $AlertsUser.WindowsLiveID
                $_
            }

            try {
                New-ProtectionAlert -AggregationType $NewAlert.AggregationType -AlertBy $NewAlert.AlertBy -AlertFor $NewAlert.AlertFor -Category $NewAlert.Category -Comment $NewAlert.Comment -CorrelationPolicyId $NewAlert.CorrelationPolicyId -CustomProperties $NewAlert.CustomProperties -Description $NewAlert.Description -Disabled $NewAlert.Disabled -Filter $NewAlert.Filter -LogicalOperationName $NewAlert.LogicalOperationName -Name $NewAlert.Name -NotificationCulture $NewAlert.NotificationCulture -NotificationEnabled $NewAlert.NotificationEnabled -NotifyUser $NewAlert.NotifyUser -NotifyUserOnFilterMatch $NewAlert.NotifyUserOnFilterMatch -NotifyUserSuppressionExpiryDate $NewAlert.NotifyUserSuppressionExpiryDate -NotifyUserThrottleThreshold $NewAlert.NotifyUserThrottleThreshold -NotifyUserThrottleWindow $NewAlert.NotifyUserThrottleWindow -Operation $NewAlert.Operation -PrivacyManagementScopedSensitiveInformationTypes $NewAlert.PrivacyManagementScopedSensitiveInformationTypes -PrivacyManagementScopedSensitiveInformationTypesForCounting $NewAlert.PrivacyManagementScopedSensitiveInformationTypesForCounting -PrivacyManagementScopedSensitiveInformationTypesThreshold $NewAlert.PrivacyManagementScopedSensitiveInformationTypesThreshold -Severity $NewAlert.Severity -ThreatType $NewAlert.ThreatType -Threshold $NewAlert.Threshold -TimeWindow $NewAlert.TimeWindow -UseCreatedDateTime $NewAlert.UseCreatedDateTime -VolumeThreshold $NewAlert.VolumeThreshold -ErrorAction Stop | Out-Null
                $AlertNames += $NewAlert.Name
            } catch {
                Write-Warning "Unable to create custom alert for $($Alert.Name)."
                $UnableToCreate += $Alert.Name
            }
        } else {
            Set-ProtectionAlert -Identity $Alert.Name -NotifyUser $AlertsUser.WindowsLiveID | Out-Null
        }
    }

    if ($UnableToCreate.Count -gt 0) {
        Write-Warning "Unable to create custom alerts for the following alerts: $($UnableToCreate -join ', ')"
        Write-Warning "Please update these alerts manually at ``https://security.microsoft.com/alertpoliciesv2`` for alerts user ``$($AlertsUser.UserPrincipalName)``."
    }
}

#endregion - Alerts and Notifications

#region - Conditional Access Policies

function New-ConditionalAccessPrivilegedIdentityManagementPolicy {
    Connect-Service AzureAD;

    #region - Const Variables
    $Local:PolicyName = 'Privileged Identity Managementt'
    $Local:DirectoryRoles = @('Application administrator', 'Authentication administrator', 'Billing administrator', 'Cloud application administrator', 'Conditional Access administrator', 'Exchange administrator', 'Global administrator', 'Global reader', 'Helpdesk administrator', 'Password administrator', 'Privileged authentication administrator', 'Privileged role administrator', 'Security administrator', 'SharePoint administrator', 'User administrator')
    #endregion

    $Local:ExistingPolicy = Get-AzureADMSConditionalAccessPolicy | Where-Object { $_.DisplayName -eq $Local:PolicyName }

    # TODO :: Check if policy is configured correctly
    if ($Local:ExistingPolicy) {
        Write-Host 'Privileged Identity Management policy already exists. Skipping...'
        return
    }

    [Microsoft.Open.MSGraph.Model.ConditionalAccessConditionSet]$Local:Conditions = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessConditionSet
    # Apply to all cloud applications
    $Local:Conditions.Applications = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessApplicationCondition
    $Local:Conditions.Applications.IncludeApplications = 'All'
    # Apply to administator roles
    $Local:Conditions.Users = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessUserCondition
    $Local:Conditions.Users.IncludeRoles = Get-AzureADMSRoleDefinition | Where-Object { $Local:DirectoryRoles -contains $_.DisplayName } | Select-Object -ExpandProperty Id

    [Microsoft.Open.MSGraph.Model.ConditionalAccessGrantControls]$Local:GrantControls = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessGrantControls
    # Enforce MFA
    $Local:GrantControls._Operator = 'OR'
    $Local:GrantControls.BuiltInControls = @('mfa')

    [Microsoft.Open.MSGraph.Model.ConditionalAccessSessionControls]$Local:SessionControls = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessSessionControls
    # Disable persistent browser
    $Local:SessionControls.PersistentBrowser = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessPersistentBrowser
    $Local:SessionControls.PersistentBrowser.IsEnabled = $true
    $Local:SessionControls.PersistentBrowser.Mode = 'Never'
    # Require Re-authentication every 4 hours
    $Local:SessionControls.SignInFrequency = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessSignInFrequency
    $Local:SessionControls.SignInFrequency.IsEnabled = $true
    $Local:SessionControls.SignInFrequency.Value = '4'
    $Local:SessionControls.SignInFrequency.Type = 'hours'

    New-AzureADMSConditionalAccessPolicy -DisplayName $Local:PolicyName -State 'Enabled' -Conditions $Local:Conditions -GrantControls $Local:GrantControls -SessionControls $Local:SessionControls -ErrorAction Stop | Out-Null
}

#endregion - Conditional Access Policies

Invoke-RunMain $PSCmdlet {
    switch ($Action) {
        'SecurityAlerts' {
            $AlertsUser = Get-AlertsUser
            if ($AlertsUser) {
                $Continue = $Host.UI.PromptForChoice("Alerts User: $($AlertsUser.WindowsLiveID)", 'Is this the correct alerts user?', @('&Yes', '&No'), 0)
                if ($Continue -eq 1) {
                    Write-Host "Please update the alerts user manually at ``https://admin.microsoft.com/Adminportal/Home#/users``."
                    exit 1003
                }

                Set-SecurityAndCompilenceAlerts -AlertsUser $AlertsUser
            }
        }
        'ConditionalAccess' {
            New-ConditionalAccessPrivilegedIdentityManagementPolicy;
        }
        'Sharepoint' {
        }
    }
};
