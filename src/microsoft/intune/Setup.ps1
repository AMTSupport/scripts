<#
.NOTES
    Before use must opt into beta shcemas, after logging into MSGraph run Update-MSGraphEnvironment -SchemaVersion 'beta';
#>

#Requires -Modules Microsoft.Graph.Authentication,Microsoft.Graph.Beta.DeviceManagement,Microsoft.Graph.Beta.Groups

using namespace Microsoft.Graph.Beta.PowerShell.Models;

#region - Utilities functions

function Get-IntuneGroup {
    $Local:GroupName = "Intune Users";
    $Local:IntuneGroup = Get-MgBetaGroup -Filter "displayName eq '$Local:GroupName'" -All:$true;

    if (-not $Local:IntuneGroup) {
        Info "$Local:GroupName does not exists. Creating...";
        $Local:IntuneGroup = New-MgBetaGroup `
            -DisplayName $Local:GroupName `
            -MailEnabled:$False `
            -MailNickname "intune" `
            -SecurityEnabled:$True `
            -Description 'Group for users that are managed by Intune.';
    }

    return $IntuneGroup
}

#endregion - Utilities functions

#region - Device Compliance Policies

function Local:Set-DeviceCompliancePolicy(
    [Parameter(Mandatory)][MicrosoftGraphGroup]$IntuneGroup,
    [Parameter(Mandatory, ValueFromPipeline)][PSCustomObject]$PolicyConfiguration
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        Trap {
            Invoke-Error 'Failed to set device compliance policy.';
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        }

        $Local:PolicyName = $PolicyConfiguration.displayName;
        $Local:ExistingPolicy = Get-MgBetaDeviceManagementDeviceCompliancePolicy -Filter "displayName eq '$Local:PolicyName'";

        if ($null -ne $Local:ExistingPolicy) {
            Info "Updating configuration profile '$Local:PolicyName'.";

            $Local:PolicyId = $Local:ExistingPolicy.Id;
            $Local:JsonPolicy = $PolicyConfiguration | ConvertTo-Json -Depth 99;
            Update-MgBetaDeviceManagementDeviceCompliancePolicy `
                -DeviceCompliancePolicyId $Local:PolicyId `
                -BodyParameter $Local:JsonPolicy;
        } else {
            Info "Creating configuration profile '$Local:PolicyName'.";

            $PolicyConfiguration | Add-Member -MemberType NoteProperty -Name 'scheduledActionsForRule' @(@{
                ruleName                      = 'PasswordRequired';
                scheduledActionConfigurations = @(@{
                        'actionType'                = 'block';
                        'gracePeriodHours'          = 0;
                        'notificationTemplateId'    = '';
                        'notificationMessageCCList' = @();
                    });
            });
            $Local:JsonPolicy = $PolicyConfiguration | ConvertTo-Json -Depth 99;
            $Local:SubmittedPolicy = New-MgBetaDeviceManagementDeviceCompliancePolicy -BodyParameter $Local:JsonPolicy;
            $Local:PolicyId = $Local:SubmittedPolicy.Id;
        }

        # Assign the policy
        Info "Assigning configuration profile '$Local:PolicyName'.";
        $Local:ExistingAssignment = Get-MgBetaDeviceManagementDeviceCompliancePolicyAssignment -DeviceCompliancePolicyId $Local:PolicyId;
        $Local:Assignment = @{
            assignments = @(
                @{
                    id = if ($Local:ExistingAssignment) { $Local:ExistingAssignment.Id } else { '00000000-0000-0000-0000-000000000000' };
                    target = @{
                        '@odata.type'   = '#microsoft.graph.groupAssignmentTarget';
                        groupId         = $IntuneGroup.Id;
                    };
                }
            );
        } | ConvertTo-Json -Depth 99;

        if (-not $Local:ExistingAssignment) {
            Info "Configuration profile '$Local:PolicyName' does not have an assignment, creating.";

            # Why must i manually invoke this?
            Invoke-MgGraphRequest -Method POST -Uri "/beta/deviceManagement/deviceCompliancePolicies/${Local:PolicyId}/assign" -Body $Local:Assignment;
        } else {
            Info "Configuration profile '$Local:PolicyName' already has an assignment, updating.";

            # Why must i manually invoke this?
            Invoke-MgGraphRequest -Method POST -Uri "/beta/deviceManagement/deviceCompliancePolicies/${Local:PolicyId}/assign" -Body $Local:Assignment;
        }
    }
}

function Local:New-CompliancePolicy(
    [Parameter(Mandatory, HelpMessage = 'The clean name of the device type.')][ValidateNotNullOrEmpty()][String]$Name,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$ODataType,
    [Parameter(Mandatory)][HashTable]$Configuration
) {
    $Configuration | Add-Member -MemberType NoteProperty -Name '@odata.type' -Value $ODataType;
    $Configuration | Add-Member -MemberType NoteProperty -Name 'RoleScopeIds' -Value @('0');
    $Configuration | Add-Member -MemberType NoteProperty -Name 'Id' -Value '00000000-0000-0000-0000-000000000000';

    $Configuration | Add-Member -MemberType NoteProperty -Name 'displayName' -Value "$Name - Baseline";
    $Configuration | Add-Member -MemberType NoteProperty -Name 'description' -Value "Baseline configuration profile for $Name devices.";

    return $Configuration;
}

function New-DeviceCompliancePolicy_Windows {
    New-CompliancePolicy 'Windows' '#microsoft.graph.windows10CompliancePolicy' @{
        passwordRequired                        = $true;
        passwordBlockSimple                         = $true;
        passwordRequiredToUnlockFromIdle            = $true;
        passwordMinutesOfInactivityBeforeLock       = 15;
        passwordExpirationDays                      = 730;
        passwordMinimumLength                       = 6;
        passwordMinimumCharacterSetCount            = $null;
        passwordRequiredType                        = 'deviceDefault';
        passwordPreviousPasswordBlockCount      = 5;

        requireHealthyDeviceReport              = $true;
        osMinimumVersion                        = $null;
        osMaximumVersion                        = $null;
        mobileOsMinimumVersion                  = $null;
        mobileOsMaximumVersion                  = $null;

        earlyLaunchAntiMalwareDriverEnabled         = $false;
        bitLockerEnabled                            = $true;
        secureBootEnabled                           = $true;
        codeIntegrityEnabled                        = $true;
        #memoryIntegrityEnabled                      = $true;
        #kernelDmaProtectionEnabled                  = $true;
        #virtualizationBasedSecurityEnabled          = $true;
        #firmwareProtectionEnabled                   = $true;
        storageRequireEncryption                    = $false;
        activeFirewallRequired                      = $true;
        defenderEnabled                             = $true;
        defenderVersion                             = $null;
        signatureOutOfDate                          = $true;
        rtpEnabled                                  = $true;
        antivirusRequired                           = $true;
        antiSpywareRequired                         = $false;
        deviceThreatProtectionEnabled               = $true;
        deviceThreatProtectionRequiredSecurityLevel = 'low';
        configurationManagerComplianceRequired      = $false;
        tpmRequired                                 = $true;
        deviceCompliancePolicyScript = $null
        validOperatingSystemBuildRanges = @();
    };
}

function New-DeviceCompliancePolicy_Android {
    New-CompliancePolicy 'Android' '#microsoft.graph.androidWorkProfileCompliancePolicy' @{
        passwordRequired            = $true
        passwordRequiredType        = 'deviceDefault'
        requiredPasswordComplexity  = 'medium'
        passwordMinutesOfInactivityBeforeLock = 15

        securityPreventInstallAppsFromUnknownSources        = $false
        securityDisableUsbDebugging                         = $false
        securityRequireVerifyApps                           = $false
        securityBlockJailbrokenDevices                      = $false
        securityBlockDeviceAdministratorManagedDevices      = $true
        securityRequireSafetyNetAttestationBasicIntegrity   = $true
        securityRequireSafetyNetAttestationCertifiedDevice  = $true
        securityRequireGooglePlayServices                   = $true
        securityRequireUpToDateSecurityProviders            = $true
        securityRequireCompanyPortalAppIntegrity            = $true

        deviceThreatProtectionEnabled                   = $true
        deviceThreatProtectionRequiredSecurityLevel     = 'low'
        advancedThreatProtectionRequiredSecurityLevel   = 'low'

        osMinimumVersion = '11'
        storageRequireEncryption = $true
    };
}

function New-DeviceCompliancePolicy_MacOS {
    New-CompliancePolicy 'MacOS' '#microsoft.graph.macOSCompliancePolicy' @{
        passwordRequired            = $true
        passwordBlockSimple         = $true
        passwordExpirationDays      = 730
        passwordPreviousPasswordBlockCount = 5
        passwordMinimumLength       = 6
        passwordRequiredType        = 'deviceDefault'
        passwordMinutesOfInactivityBeforeLock = 15

        systemIntegrityProtectionEnabled    = $true
        deviceThreatProtectionEnabled       = $true
        storageRequireEncryption            = $true
        firewallEnabled                     = $true
        firewallBlockAllIncoming            = $false
        firewallEnableStealthMode           = $true
        gatekeeperAllowedAppSource          = 'macAppStoreAndIdentifiedDevelopers'
    };
}

function New-DeviceCompliancePolicy_iOS {
    New-CompliancePolicy 'iOS' '#microsoft.graph.iosCompliancePolicy' @{
        passcodeBlockSimple = $true
        passcodeExpirationDays = 65535
        passcodeMinimumLength = 6
        passcodeMinutesOfInactivityBeforeLock = 15
        passcodeMinutesOfInactivityBeforeScreenTimeout = 15
        passcodePreviousPasscodeBlockCount = 5
        passcodeRequiredType = 'deviceDefault'
        passcodeRequired = $true

        securityBlockJailbrokenDevices = $true
        deviceThreatProtectionEnabled = $true
        deviceThreatProtectionRequiredSecurityLevel = 'low'
        advancedThreatProtectionRequiredSecurityLevel = 'low'
        managedEmailProfileRequired = $false
    };
}


#region - Device Configuration Profiles

function Local:Set-DeviceConfigurationProfile([String]$Local:Name, [Parameter(ValueFromPipeline)][PSCustomObject]$Local:Configuration) {
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
Import-Module $PSScriptRoot/../../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    Connect-Service -Services 'Graph'; # Scopes needed, deviceManagementConfiguration.ReadWrite.All,Group.ReadWrite.All,

    # Setup the Intune Group
    [MicrosoftGraphGroup]$Local:IntuneGroup = Get-IntuneGroup

    # Setup the Device Compliance Policies
    [PSCustomObject[]]$Local:DeviceCompliancePolicies = @((New-DeviceCompliancePolicy_Windows), (New-DeviceCompliancePolicy_Android), (New-DeviceCompliancePolicy_MacOS), (New-DeviceCompliancePolicy_iOS));
    $Local:DeviceCompliancePolicies | ForEach-Object {
        Set-DeviceCompliancePolicy -IntuneGroup $Local:IntuneGroup -PolicyConfiguration $_;
    }

    # Setup the Device Configuration Profiles
    [PSCustomObject[]]$Local:DeviceConfigurationProfiles = @();
    $Local:DeviceConfigurationProfiles | ForEach-Object {
        Local:Set-DeviceConfigurationProfile -Name $_.Name -Configuration $_.Configuration;
    }
};
