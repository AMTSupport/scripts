#Requires -Version 5.1
#Requires -Modules AzureADPreview

function New-Condition_AllCloudApps(
    [Parameter(Mandatory)]
    [Microsoft.Open.MSGraph.Model.ConditionalAccessConditionSet]$Conditions
) {
    $Conditions.Applications = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessApplicationCondition
    $Conditions.Applications.IncludeApplications = 'All'
}

function New-Condition_UserRoles(
    [Parameter(Mandatory)]
    [Microsoft.Open.MSGraph.Model.ConditionalAccessConditionSet]$Conditions,

    [Parameter(Mandatory)]
    [String[]]$DirectoryRoles
) {
    $Conditions.Users = New-Object -TypeName Microsoft.Open.MSGraph.Model.ConditionalAccessUserCondition
    $Conditions.Users.IncludeRoles = Get-AzureADMSRoleDefinition | Where-Object { $Local:DirectoryRoles -contains $_.DisplayName } | Select-Object -ExpandProperty Id
}

function Invoke-EnsureGroup {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,

        [Parameter(Mandatory)]
        [String]$Description
    )

    process {
        $Local:Group = Get-AzureADGroup -Filter "DisplayName eq '$Name'";
        if (-not $Local:Group) {
            Write-Host "Creating security group '$Name'...";
            $Local:Group = New-AzureADGroup -DisplayName $Name -MailEnabled $false -SecurityEnabled $true -MailNickName $Name -Description $Description;
        }

        return $Local:Group;
    }
}

function Invoke-EnsureLocation {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Name
    )

    process {
        $Local:Location = Get-AzureADMSNamedLocation | Where-Object { $_.DisplayName -eq $DisplayName };
        if (-not $Local:Location) {
            Write-Host "Creating named location '$DisplayName'...";
            $Local:Location = New-AzureADMSNamedLocation -DisplayName $DisplayName -Address $Address;
        }

        return $Local:Location;
    }
}

function Update-GeoBlock {
    process {
        $Local:Group = Invoke-EnsureGroup -Name 'GeoBlock - Allow Travel' -Description 'Allow travel for users in this group';
        $Local:BlockedLocations = Get-AzureADMSBlockedLocation | Where-Object { $_.DisplayName -eq 'GeoBlock - Blocked Locations' };

        # Ensure that the conditional access named locations exists
        $Local:NamedLocation
        $Local:Locations = Get-AzureADMSNamedLocation | Where-Object { $_.DisplayName -eq $Local:Group };
    }
}

function New-ConditionalAccessPrivilegedIdentityManagementPolicy {

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
    New-Condition_AllCloudApps -Conditions $Local:Conditions
    New-Condition_UserRoles -Conditions $Local:Conditions -DirectoryRoles $Local:DirectoryRoles

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


Import-Module $PSScriptRoot/../../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    Connect-Service AzureAD;
};
