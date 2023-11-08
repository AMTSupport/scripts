#Requires -Modules Microsoft.Graph.Intune, Microsoft.Graph

Param(
    [Parameter(ValueFromRemainingArguments)]
    [String[]]$SharepointLibraries,

    [Parameter(DontShow)]
    [Microsoft.Open.AzureAD.Model.Group]$Script:IntuneGroup = { Get-IntuneGroup }
)

#region - Utilities functions

function Assert-Connection {
    if ($null -eq (Get-IntuneDeviceAppManagement -ErrorAction SilentlyContinue)) {
        try {
            Connect-MSGraph
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
    Assert-Connection

    $TenantId = Get-TenantId
    $IntuneGroup = Get-AzureADGroup -Filter "DisplayName eq 'Intune Users'" -All $true | Where-Object {
        $_.ExtensionProperty -match "deviceManagement" -and $_.ExtensionProperty.deviceManagement -match $TenantId
    }

    if ($null -eq $IntuneGroup) {
        # Create the group
        $IntuneGroup = New-AzureADGroup -DisplayName "Intune Users" -Description "Group for users that are managed by Intune." -SecurityEnabled $true -GroupTypes "Unified"
    }

    return $IntuneGroup
}

#endregion - Utilities functions

#region - Device Compliance Policies

function Local:Set-DeviceCompliancePolicy([String]$Local:Name, [Parameter(ValueFromPipeline)][PSCustomObject]$Local:Policy) {
    Assert-Connection

    if ($null -eq $Local:Name) {
        throw "Name cannot be null."
    }

    if ($null -eq $Local:Configuration) {
        throw "Configuration cannot be null."
    }

    $Local:ExistingPolicy = Get-IntuneDeviceCompliancePolicy -Filter "displayName eq '$Name'";

    # Check if the policy is already set to the correct configuration
    if ($null -ne $Local:ExistingPolicy -and $Local:ExistingPolicy.Json -eq ($Local:Policy | ConvertTo-Json)) {
        Write-Host "Configuration profile '$Local:Name' is already set to the correct configuration.";
        return
    } elseif ($null -ne $Local:ExistingPolicy) {
        # Remove the existing policy
        Write-Host "Removing existing configuration profile '$Local:Name'.";
        Remove-IntuneDeviceCompliancePolicy -Id $Local:ExistingPolicy.Id;
    }

    # Create the policy
    Write-Host "Creating configuration profile '$Local:Name'.";
    $Local:SubmittedPolicy = New-IntuneDeviceCompliancePolicy `
        -displayName $Local:Name `
        -description "Baseline configuration profile for $Local:Name devices." `
        @Local:Policy;


    # Assign the policy
    Write-Host "Assigning configuration profile '$Local:Name'.";
    Invoke-IntuneDeviceCompliancePolicyAssign -deviceCompliancePolicyId $Local:SubmittedPolicy `
        -assignments (New-DeviceCompliancePolicyAssignmentObject `
            -target (New-DeviceAndAppManagementAssignmentTargetObject `
                -groupAssignmentTarget `
                -groupId $Script:IntuneGroup.Id `
            ));
}

#region - Windows Compliance Policies

function Set-DeviceCompliancePolicy_Windows {
    [String]$Local:Name = "Windows - Baseline"

    [PSCustomObject]@{
        windows10CompliancePolicy = $true

        bitLockerEnabled = $true
        secureBootEnabled = $true
        codeIntegrityEnabled = $true
    } | Local:Set-DeviceCompliancePolicy -Name $Local:Name
}

#endregion - Windows Compliance Policies
#region - Android Compliance Policies
#endregion - Android Compliance Policies
#region - Apple Compliance Policies
#endregion - Apple Compliance Policies
#endregion - Device Compliance Policies
#region - Device Configuration Profiles

function Local:Set-DeviceConfigurationProfile([String]$Local:Name, [Parameter(ValueFromPipeline)][PSCustomObject]$Local:Configuration) {
    Assert-Connection

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
