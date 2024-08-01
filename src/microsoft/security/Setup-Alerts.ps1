#Requires -Version 5.1

param(
    [Parameter()]
    [Switch]$UpdatePolicies
)

function Update-SecurityAndCompilence(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [PSObject]$AlertsUser
) {
    $Local:Alerts = Get-ProtectionAlert
    $Local:AlertNames = $Local:Alerts | Select-Object -ExpandProperty Name
    $Local:Alerts = $Local:Alerts | Where-Object { ($_.NotifyUser -ne $AlertsUser.WindowsLiveID) -and !$_.Disabled }

    if ($null -eq $Local:Alerts -or $Local:Alerts.Count -eq 0) {
        Info 'All Security and Complience alerts are already configured to notify the Alerts user.';
        return;
    }

    $Local:UnableToCreate = @()
    foreach ($Local:Alert in $Local:Alerts) {
        if ($Local:Alert.IsSystemRule) {
            # Check for existing custom rule
            if ($Local:AlertNames -contains "AMT $($Local:Alert.Name)") {
                Info "Custom alert already exists for $($Local:Alert.Name). Skipping...";
                continue;
            }

            # We need to re-create this as a custom rule so we can modify the NotifyUser property
            $Local:NewAlert = $Local:Alert | Select-Object -Property * | ForEach-Object {
                $_.Name = "AMT $($_.Name)"
                $_.NotifyUser = $AlertsUser.WindowsLiveID
                $_
            }

            try {
                New-ProtectionAlert -AggregationType $Local:NewAlert.AggregationType -AlertBy $Local:NewAlert.AlertBy -AlertFor $Local:NewAlert.AlertFor -Category $Local:NewAlert.Category -Comment $Local:NewAlert.Comment -CorrelationPolicyId $Local:NewAlert.CorrelationPolicyId -CustomProperties $Local:NewAlert.CustomProperties -Description $Local:NewAlert.Description -Disabled $Local:NewAlert.Disabled -Filter $Local:NewAlert.Filter -LogicalOperationName $Local:NewAlert.LogicalOperationName -Name $Local:NewAlert.Name -NotificationCulture $Local:NewAlert.NotificationCulture -NotificationEnabled $Local:NewAlert.NotificationEnabled -NotifyUser $Local:NewAlert.NotifyUser -NotifyUserOnFilterMatch $Local:NewAlert.NotifyUserOnFilterMatch -NotifyUserSuppressionExpiryDate $Local:NewAlert.NotifyUserSuppressionExpiryDate -NotifyUserThrottleThreshold $Local:NewAlert.NotifyUserThrottleThreshold -NotifyUserThrottleWindow $Local:NewAlert.NotifyUserThrottleWindow -Operation $Local:NewAlert.Operation -PrivacyManagementScopedSensitiveInformationTypes $Local:NewAlert.PrivacyManagementScopedSensitiveInformationTypes -PrivacyManagementScopedSensitiveInformationTypesForCounting $Local:NewAlert.PrivacyManagementScopedSensitiveInformationTypesForCounting -PrivacyManagementScopedSensitiveInformationTypesThreshold $Local:NewAlert.PrivacyManagementScopedSensitiveInformationTypesThreshold -Severity $Local:NewAlert.Severity -ThreatType $Local:NewAlert.ThreatType -Threshold $Local:NewAlert.Threshold -TimeWindow $Local:NewAlert.TimeWindow -UseCreatedDateTime $Local:NewAlert.UseCreatedDateTime -VolumeThreshold $Local:NewAlert.VolumeThreshold -ErrorAction Stop | Out-Null
                $Local:AlertNames += $Local:NewAlert.Name;
            } catch {
                Warn "Unable to create custom alert for $($Local:Alert.Name).";
                $Local:UnableToCreate += $Local:Alert.Name;
            }
        } else {
            Info "Updating alert ''$($Local:Alert.Name)''..."
            Set-ProtectionAlert -Identity $Local:Alert.Name -NotifyUser $Local:AlertsUser.WindowsLiveID | Out-Null
        }
    }

    if ($Local:UnableToCreate.Count -gt 0) {
        Warn "Unable to create custom alerts for the following alerts: $($Local:UnableToCreate -join ', ')";
        Warn "Please update these alerts manually at ``https://security.microsoft.com/alertpoliciesv2`` for alerts user ``$($Local:AlertsUser.UserPrincipalName)``.";
    }
}


Import-Module $PSScriptRoot/../../common/Environment.psm1;
Invoke-RunMain $PSCmdlet {
    Connect-Service -Services SecurityComplience,Graph -Scopes 'SecurityEvents.ReadWrite.All';

    [MicrosoftGraphUser]$Local:AlertsUser = Get-AlertsUser;
    Update-SecurityAndCompilence -AlertsUser $Local:AlertsUser;
};
