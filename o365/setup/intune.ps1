#Requires -Modules Microsoft.Graph.Intune
#Requires -PSEdition Desktop
#Requires -Version 5.1

#region - Utilities functions

function Local:Assert-Connection {
    try {
        Get-AzureADCurrentSessionInfo -ErrorAction Stop | Out-Null
        Get-MSGraphEnvironment -ErrorAction Stop | Out-Null
    } catch {
        try {
            Connect-AzureAD -ErrorAction Stop;
            Connect-MSGraph -ErrorAction Stop;
        } catch {
            throw "Not connected to Azure AD."
        }
    }
}

function Get-TenantId {
    Assert-Connection

    $TenantId = Get-AzureADTenantDetail | Select-Object -ExpandProperty ObjectId
    if ($null -eq $TenantId) {
        throw "TenantId is null."
    }

    return $TenantId
}

function Get-IntuneGroup {
    $Local:GroupName = "Intune";
    Assert-Connection

    $Local:IntuneGroup = Get-AzureADGroup -Filter "DisplayName eq '$Local:GroupName'" -All $true;
    if ($null -eq $IntuneGroup) {
        # Create the group
        $IntuneGroup = New-AzureADGroup -DisplayName $Local:GroupName -Description "Group for users that are managed by Intune." -SecurityEnabled $true;
    }

    return $IntuneGroup
}

#endregion - Utilities functions

#region - Device Compliance Policies

function Local:Set-DeviceCompliancePolicy(
    [Parameter(Mandatory)][Microsoft.Open.AzureAD.Model.Group]$Local:IntuneGroup,
    [Parameter(Mandatory, ValueFromPipeline)][PSCustomObject]$Local:PolicyConfiguration
) {
    Local:Assert-Connection

    if ($null -eq $Local:PolicyConfiguration) {
        throw "Configuration cannot be null."
    }

    [String]$Local:PolicyName = $Local:PolicyConfiguration.displayName;
    if ($null -eq $Local:PolicyName) {
        throw "Name cannot be null."
    }

    $Local:ExistingPolicy = Get-IntuneDeviceCompliancePolicy -Filter "displayName eq '$Local:PolicyName'";

    # Check if the policy is already set to the correct configuration
    if ($null -ne $Local:ExistingPolicy -and $Local:ExistingPolicy.Json -eq ($Local:PolicyConfiguration | ConvertTo-Json)) {
        Write-Host "Configuration profile '$Local:PolicyName' is already set to the correct configuration.";
        return
    } elseif ($null -ne $Local:ExistingPolicy) {
        # Remove the existing policy
        Write-Host "Removing existing configuration profile '$Local:PolicyName'.";
        Remove-IntuneDeviceCompliancePolicy -Id $Local:ExistingPolicy.Id;
    }

    # Create the policy
    Write-Host "Creating configuration profile '$Local:PolicyName'.";
    $Local:SubmittedPolicy = New-IntuneDeviceCompliancePolicy `
        -displayName $Local:PolicyName `
        -description "Baseline configuration profile for $Local:PolicyName devices." `
        @Local:PolicyConfiguration;


    # Assign the policy
    Write-Host "Assigning configuration profile '$Local:PolicyName'.";
    Invoke-IntuneDeviceCompliancePolicyAssign -deviceCompliancePolicyId $Local:SubmittedPolicy `
        -assignments (New-DeviceCompliancePolicyAssignmentObject `
            -target (New-DeviceAndAppManagementAssignmentTargetObject `
                -groupAssignmentTarget `
                -groupId $Local:IntuneGroup.Id `
            ));
}

#region - Windows Compliance Policies

function New-DeviceCompliancePolicy_Windows {
    [PSCustomObject]@{
        displayName = "Windows - Baseline"

        windows10CompliancePolicy = $true

        bitLockerEnabled = $true
        secureBootEnabled = $true
        codeIntegrityEnabled = $true
    }
}

#endregion - Windows Compliance Policies
#region - Android Compliance Policies
#endregion - Android Compliance Policies
#region - Apple Compliance Policies
#endregion - Apple Compliance Policies
#endregion - Device Compliance Policies

#region - Device Configuration Profiles

function Local:Set-DeviceConfigurationProfile([String]$Local:Name, [Parameter(ValueFromPipeline)][PSCustomObject]$Local:Configuration) {
    Local:Assert-Connection

    if ($null -eq $Local:Name) {
        throw "Name cannot be null."
    }

    if ($null -eq $Local:Configuration) {
        throw "Configuration cannot be null."
    }

    $Local:ExistingPolicy = Get-IntuneDeviceConfigurationPolicy -Filter "displayName eq '$Name'";

    # Check if the policy is already set to the correct configuration
    if ($null -ne $Local:ExistingPolicy -and $Local:ExistingPolicy.Json -eq ($Local:Configuration | ConvertTo-Json)) {
        Write-Host "Configuration profile '$Local:Name' is already set to the correct configuration.";
        return
    } elseif ($null -ne $Local:ExistingPolicy) {
        # Remove the existing policy
        Write-Host "Removing existing configuration profile '$Local:Name'.";
        Remove-IntuneDeviceConfigurationPolicy -Id $Local:ExistingPolicy.Id;
    }

    # Create the policy
    Write-Host "Creating configuration profile '$Local:Name'.";
    $Local:SubmittedConfiguration = New-IntuneDeviceConfigurationPolicy `
        -displayName $Local:Name `
        -description "Baseline configuration profile for $Local:Name devices." `
        @Local:Configuration;


    # Assign the policy
    Write-Host "Assigning configuration profile '$Local:Name'.";
    Invoke-IntuneDeviceConfigurationPolicyAssign -deviceConfigurationId $Local:SubmittedConfiguration `
        -assignments (New-IntuneDeviceConfigurationPolicyAssignment `
            -target (New-DeviceAndAppManagementAssignmentTargetObject `
                -groupAssignmentTarget `
                -groupId $Script:IntuneGroup.Id `
        ));
}

#region - Windows Configuration Profiles

function Set-DeviceWindowsConfigurationProfile_OneDrive {
    $Local:Name = "Windows - OneDrive"

    # Custom Policy
    [PSCustomObject]@{

    } | Local:Set-DeviceConfigurationProfile -Name $Local:Name
}

function Set-DeviceWindowsConfigurationProfile_Encryption {
    $Local:Name = "Windows - Encryption"
    # Custom Policy and Endpoint Protector Template
}

function Set-DeviceWindowsConfigurationProfile_DomainJoin {
    $Local:Name = "Windows - Domain Join"
    # Templates - Domain Join

    # Computer Name Prefix (auto-generated based on company name) : (Eg: AMT-)
    # Domain Name (get from Azure AD) : (Eg: amt.com.au)
}

function Set-DeviceWindowsConfigurationProfile_IdentityProtection {
    $Local:Name = "Windows - Identity Protection"
    # Templates - Identity Protection

    # E 6 - A A A N - N E E E N N
}

#endregion - Windows Configuration Profiles
#region - MacOS Configuration Profiles
#endregion - MacOS Configuration Profiles
#endregion - Device Configuration Profiles

#region - Conditional Access Policies

function Set-TemplatePolicies {
    ## Definitly these
    # Require multifactor authentication for admins
    # Require multifactor authentication for all users
    # Block Legacy Authentication

    ## Maybes these too?
    # Securing security info registration
    # Block access for unkown or unsupported device platform
    # Require password change for high-risk users
}

function Set-CustomPolicies {
    # Geoblock
    # Geoblock - Allow Travel
}

#endregion - Conditional Access Policies

#region - Endpoint Security

#region - Antivirus

function Set-EndpointSecurityAntivirusWindows {

}

function Set-EndpointSecurityAntivirusMacOS {

}

function Set-EndpointSecurityAntivirusLinux {

}

#endregion - Antivirus

#region - Disk Encryption

function Set-EndpointSecurityEncryptionWindows {

}

function Set-EndpointSecurityEncryptionMacOS {

}

#endregion - Disk Encryption

#endregion - Endpoint Security

function Invoke-Main {
    # Get Connections
    Assert-Connection

    # Setup the Intune Group
    [Microsoft.Open.AzureAD.Model.Group]$Local:IntuneGroup = Get-IntuneGroup

    # Setup the Device Compliance Policies
    [PSCustomObject[]]$Local:DeviceCompliancePolicies = @(New-DeviceCompliancePolicy_Windows);
    $Local:DeviceCompliancePolicies | ForEach-Object {
        Local:Set-DeviceCompliancePolicy -IntuneGroup $Local:IntuneGroup -PolicyConfiguration $_;
    }

    # Setup the Device Configuration Profiles
    [PSCustomObject[]]$Local:DeviceConfigurationProfiles = @();
    $Local:DeviceConfigurationProfiles | ForEach-Object {
        Local:Set-DeviceConfigurationProfile -Name $_.Name -Configuration $_.Configuration;
    }

    # Setup the Conditional Access Policies
}

# If the script is being run directly, invoke the main function
if ($MyInvocation.CommandOrigin -eq 'Runspace') {
    Invoke-Main
} else {
    Write-Host "Script is being imported."
    Write-Host $MyInvocation.CommandOrigin
}
