<#
.NOTES
    Before use, must opt into beta shcemas, after logging into MSGraph run Update-MSGraphEnvironment -SchemaVersion 'beta';
#>

#Requires -Modules Microsoft.Graph.Authentication,Microsoft.Graph.Beta.DeviceManagement,Microsoft.Graph.Beta.Groups

using namespace Microsoft.Graph.Beta.PowerShell.Models;

[CmdletBinding()]
param()

#region - Utilities functions

function Get-IntuneGroup {
    $Local:GroupName = "Intune Users";
    $Local:IntuneGroup = Get-MgBetaGroup -Filter "displayName eq '$Local:GroupName'" -All:$true;

    if (-not $Local:IntuneGroup) {
        Invoke-Info "$Local:GroupName does not exists. Creating...";
        $Local:IntuneGroup = New-MgBetaGroup `
            -DisplayName $Local:GroupName `
            -MailEnabled:$False `
            -MailNickname "intune" `
            -SecurityEnabled:$True `
            -Description 'Group for users that are managed by Intune.';
    }

    return $IntuneGroup
}

function Local:Set-Configuration(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [MicrosoftGraphGroup]$IntuneGroup,

    [Parameter(Mandatory, ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [PSCustomObject]$Configuration,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]$GetExistingConfiguration,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]$UpdateConfiguration,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]$NewConfiguration,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]$NewConfigurationExtra,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]$GetExistingAssignment,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]$UpdateAssignment,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]$NewAssignment
) {
    begin { Enter-Scope -IgnoreParams 'GetExistingConfiguration', 'UpdateConfiguration', 'NewConfiguration', 'NewConfigurationExtra', 'GetExistingAssignment', 'UpdateAssignment', 'NewAssignment' }
    end { Exit-Scope; }

    process {
        Trap {
            Invoke-Error 'Failed to set device compliance policy.';
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        }

        [String]$Local:ConfigurationName = $Configuration.displayName;
        $Local:ExistingConfiguration = $GetExistingConfiguration.InvokeReturnAsIs(@($Local:ConfigurationName));

        if ($null -ne $Local:ExistingConfiguration) {
            Invoke-Info "Updating configuration '$Local:ConfigurationName'.";

            # Compare the existing policy to the new policy
            [Boolean]$Local:ConfigurationIsDifferent = $false;
            foreach ($Local:Property in $Configuration.GetEnumerator()) {
                if ($Local:Property.Value -ne $Local:ExistingConfiguration.AdditionalProperties."$($Local:Property.Name)") {
                    Invoke-Info "Property '$($Local:Property.Name)' is different, updating.";
                    Invoke-Debug "Old: $($Local:ExistingConfiguration.AdditionalProperties.$Local:Property.Name)";
                    Invoke-Debug "New: $($Local:Property.Value)";

                    $Local:ConfigurationIsDifferent = $true;
                    break;
                }
                else {
                    Invoke-Debug "Property '$($Local:Property.Name)' is the same, skipping.";
                }
            }

            if (-not $Local:ConfigurationIsDifferent) {
                Invoke-Info "Configuration '$Local:ConfigurationName' is already set to the correct configuration.";
                return;
            }

            [String]$Local:ConfigurationId = $Local:ExistingConfiguration.Id;
            [String]$Local:JsonConfiguration = $Configuration | ConvertTo-Json -Depth 99;
            $UpdateConfiguration.InvokeReturnAsIs(@($Local:ConfigurationId, $Local:JsonConfiguration));
        }
        else {
            Invoke-Info "Creating configuration '$Local:ConfigurationName'.";

            if ($null -ne $NewConfigurationExtra) {
                $Configuration = $NewConfigurationExtra.InvokeReturnAsIs(@($Configuration));
            }

            [String]$Local:JsonConfiguration = $Configuration | ConvertTo-Json -Depth 99;
            try {
                $ErrorActionPreference = 'Stop';
                $Local:SubmittedConfiguration = $NewConfiguration.InvokeReturnAsIs(@($Local:JsonConfiguration));
            } catch {
                Invoke-Error 'There was an error creating the configuration.';
                Invoke-FailedExit -ExitCode 1001 -ErrorRecord $_;
            }

            [String]$Local:ConfigurationId = $Local:SubmittedConfiguration.Id;
        }

        # Assign the policy
        Invoke-Info "Assigning configuration '$Local:ConfigurationName'.";
        $Local:ExistingAssignment = $GetExistingAssignment.InvokeReturnAsIs(@($Local:ConfigurationId));
        $Local:Assignment = @{
            assignments = @(
                @{
                    id     = if ($Local:ExistingAssignment) { $Local:ExistingAssignment.Id } else { '00000000-0000-0000-0000-000000000000' };
                    target = @{
                        '@odata.type' = '#microsoft.graph.groupAssignmentTarget';
                        groupId       = $IntuneGroup.Id;
                    };
                }
            );
        } | ConvertTo-Json -Depth 99;

        if (-not $Local:ExistingAssignment) {
            Invoke-Info "Configuration '$Local:ConfigurationName' does not have an assignment, creating.";

            $NewAssignment.InvokeReturnAsIs(@($Local:ConfigurationId, $Local:Assignment));
        } else {
            Invoke-Info "Configuration '$Local:ConfigurationName' already has an assignment, updating.";

            $UpdateAssignment.InvokeReturnAsIs(@($Local:ConfigurationId, $Local:Assignment));
        }
    }
}

#endregion - Utilities functions

#region - Device Compliance Policies

function Local:Set-DeviceCompliancePolicy(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [MicrosoftGraphGroup]$IntuneGroup,

    [Parameter(Mandatory, ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [PSCustomObject]$PolicyConfiguration
) {
    Set-Configuration `
        -IntuneGroup $IntuneGroup `
        -Configuration $PolicyConfiguration `
        -GetExistingConfiguration { param($Name) Get-MgBetaDeviceManagementDeviceCompliancePolicy -Filter "displayName eq '$Name'" } `
        -UpdateConfiguration { param($Id, $Json) Update-MgBetaDeviceManagementDeviceCompliancePolicy -DeviceCompliancePolicyId $Id -BodyParameter $Json } `
        -NewConfiguration { param($Json) New-MgBetaDeviceManagementDeviceCompliancePolicy -BodyParameter $Json } `
        -NewConfigurationExtra { param($Configuration) $Configuration | Add-Member -MemberType NoteProperty -Name 'scheduledActionsForRule' @(@{
                ruleName                      = 'PasswordRequired';
                scheduledActionConfigurations = @(@{
                        'actionType'                = 'block';
                        'gracePeriodHours'          = 0;
                        'notificationTemplateId'    = '';
                        'notificationMessageCCList' = @();
                    });
            }) } `
        -GetExistingAssignment { param($Id) Get-MgBetaDeviceManagementDeviceCompliancePolicyAssignment -DeviceCompliancePolicyId $Id } `
        -UpdateAssignment { param($Id, $Assignment) Invoke-MgGraphRequest -Method POST -Uri "/beta/deviceManagement/deviceCompliancePolicies/${Id}/assign" -Body $Assignment } `
        -NewAssignment { param($Id, $Assignment) Invoke-MgGraphRequest -Method POST -Uri "/beta/deviceManagement/deviceCompliancePolicies/${Id}/assign" -Body $Assignment }
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

function Get-CommonCompliance(
    [Parameter(Mandatory)]
    [ValidateSet('password', 'passcode')]
    [String]$PassVar,

    [Parameter(ParameterSetName = 'WithExpiration')]
    [Switch]$WithExpiration,

    [Parameter(ParameterSetName = 'WithExpiration')]
    [Int]$Expiration = 730,

    [Parameter()]
    [Switch]$WithHarden
) {
    $Local:Common = @{
        "${PassVar}Required"                        = $true;
        "${PassVar}RequiredType"                    = 'deviceDefault';
        "${PassVar}MinutesOfInactivityBeforeLock"   = 15;
    };

    if ($WithExpiration) {
        $Local:Common.Add("${PassVar}ExpirationDays", $Expiration);
    }

    if ($WithHarden) {
        $Local:Common.Add("${PassVar}BlockSimple", $true);
        $Local:Common.Add("${PassVar}MinimumLength", 6);
        $Local:Common.Add("${PassVar}PreviousP$($PassVar.SubString(1))BlockCount", 5);
    }

    return $Local:Common;
}

function New-DeviceCompliancePolicy_Windows {
    New-CompliancePolicy 'Windows' '#microsoft.graph.windows10CompliancePolicy' (@{
        passwordRequiredToUnlockFromIdle        = $true;
        passwordMinimumCharacterSetCount        = $null;

        requireHealthyDeviceReport      = $true;
        osMinimumVersion                = $null;
        osMaximumVersion                = $null;
        mobileOsMinimumVersion          = $null;
        mobileOsMaximumVersion          = $null;
        validOperatingSystemBuildRanges = @();

        tpmRequired                                 = $true;
        bitLockerEnabled                            = $true;
        secureBootEnabled                           = $true;
        codeIntegrityEnabled                        = $true;
        storageRequireEncryption                    = $true;
        earlyLaunchAntiMalwareDriverEnabled         = $false;
        # TODO: Figure out how to enable these
        #memoryIntegrityEnabled                      = $true;
        #kernelDmaProtectionEnabled                  = $true;
        #virtualizationBasedSecurityEnabled          = $true;
        #firmwareProtectionEnabled                   = $true;

        activeFirewallRequired                      = $true;
        defenderEnabled                             = $true;
        defenderVersion                             = $null;
        signatureOutOfDate                          = $true;
        rtpEnabled                                  = $false; # SentinalOne is used
        antivirusRequired                           = $true;
        antiSpywareRequired                         = $true;

        deviceThreatProtectionEnabled               = $true;
        deviceThreatProtectionRequiredSecurityLevel = 'low';

        deviceCompliancePolicyScript = $null
        configurationManagerComplianceRequired      = $false;
    } + (Get-CommonCompliance -PassVar 'password' -WithExpiration -WithHarden));
}

function New-DeviceCompliancePolicy_Android {
    New-CompliancePolicy 'Android' '#microsoft.graph.androidWorkProfileCompliancePolicy' (@{
        requiredPasswordComplexity  = 'medium'

        securityPreventInstallAppsFromUnknownSources        = $false
        securityDisableUsbDebugging                         = $false
        securityRequireVerifyApps                           = $false
        securityBlockJailbrokenDevices                      = $false
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
    } + (Get-CommonCompliance -PassVar 'password'));
}

function New-DeviceCompliancePolicy_MacOS {
    New-CompliancePolicy 'MacOS' '#microsoft.graph.macOSCompliancePolicy' (@{
        systemIntegrityProtectionEnabled    = $true
        deviceThreatProtectionEnabled       = $true
        storageRequireEncryption            = $true
        firewallEnabled                     = $true
        firewallBlockAllIncoming            = $false
        firewallEnableStealthMode           = $true
        gatekeeperAllowedAppSource          = 'macAppStoreAndIdentifiedDevelopers'
    } + (Get-CommonCompliance -PassVar 'password' -WithExpiration -WithHarden));
}

function New-DeviceCompliancePolicy_iOS {
    New-CompliancePolicy 'iOS' '#microsoft.graph.iosCompliancePolicy' (@{
        passcodeMinutesOfInactivityBeforeScreenTimeout = 15

        securityBlockJailbrokenDevices = $true
        deviceThreatProtectionEnabled = $true
        deviceThreatProtectionRequiredSecurityLevel = 'low'
        advancedThreatProtectionRequiredSecurityLevel = 'low'
        managedEmailProfileRequired = $false
    } + (Get-CommonCompliance -PassVar 'passcode' -WithExpiration -Expiration:65535 -WithHarden));
}

#endregion - Device Compliance Policies

#region - Device Configuration Profiles

function Local:Set-DeviceConfigurationProfile(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [MicrosoftGraphGroup]$IntuneGroup,

    [Parameter(Mandatory, ValueFromPipeline)]
    [ValidateNotNullOrEmpty()]
    [PSCustomObject]$Configuration
) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        Set-Configuration `
            -IntuneGroup $IntuneGroup `
            -Configuration $Configuration `
            -GetExistingConfiguration { param($Name) Get-MgBetaDeviceManagementDeviceConfiguration -Filter "displayName eq '$Name'" } `
            -UpdateConfiguration { param($Id, $Json) Update-MgBetaDeviceManagementDeviceConfiguration -DeviceConfigurationId $Id -BodyParameter $Json } `
            -NewConfiguration { param($Json) New-MgBetaDeviceManagementDeviceConfiguration -BodyParameter $Json } `
            -GetExistingAssignment { param($Id) Get-MgBetaDeviceManagementDeviceConfigurationAssignment -DeviceConfigurationAssignmentId $Id } `
            -UpdateAssignment { param($Id, $Assignment) Invoke-MgGraphRequest -Method POST -Uri "/beta/deviceManagement/deviceConfigurations/${Id}/assign" -Body $Assignment } `
            -NewAssignment { param($Id, $Assignment) Invoke-MgGraphRequest -Method POST -Uri "/beta/deviceManagement/deviceConfigurations/${Id}/assign" -Body $Assignment }
    }
}

#region - Windows Configuration Profiles

function Local:New-DeviceConfigurationProfile(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$OS,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Name,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [HashTable]$Configuration
) {
    $Configuration | Add-Member -MemberType NoteProperty -Name 'RoleScopeTagIds' -Value @('0');
    $Configuration | Add-Member -MemberType NoteProperty -Name 'Id' -Value '00000000-0000-0000-0000-000000000000';

    $Configuration | Add-Member -MemberType NoteProperty -Name 'displayName' -Value "$OS - $Name";
    $Configuration | Add-Member -MemberType NoteProperty -Name 'description' -Value "Configuration profile for $OS, configuring $Name items.";

    return $Configuration;
}

$Script:DeviceConfigurationProfiles = @(
    # (New-ConfigurationProfile 'Windows' 'Domain Policy' @{
    #     '@odata.type' = '#microsoft.graph.windowsDomainJoinConfiguration';
    #     computerNameStaticPrefix        = 'AMT-';
    #     computerNameSufixRandCharCount  = 12;
    #     activeDirectoryDomainName       = (Get-MgDomain | Where-Object { $_.IsDefault -eq $True } | Select-Object -ExpandProperty Id);
    # })
    (New-DeviceConfigurationProfile 'Windows' 'Debloat' @{
        '@odata.type' = '#microsoft.graph.windows10GeneralConfiguration';
        searchDisableUseLocation = $True;
        searchDisableLocation = $True;
        searchBlockWebResults = $True;

        diagnosticsDataSubmissionMode = 'basic';

        inkWorkspaceAccess = 'disabled';
        inkWorkspaceAccessState = 'blocked';
        inkWorkspaceBlockSuggestedApps = $True;

        lockScreenBlockCortana = $True;
        lockScreenBlockToastNotifications = $True;

        settingsBlockGamingPage = $True;

        cortanaBlocked = $True;
        windowsSpotlightBlocked = $True;
        smartScreenBlockPromptOverride = $True;
        internetSharingBlocked = $True;
        gameDvrBlocked = $True;
        uninstallBuiltInApps = $True;
    })
    # (New-DeviceConfigurationProfile 'Windows' 'Identity Protection' @{

    # })

    # TODO :: Printer Setup Conf
    # TODO :: Identity Protection Conf
    # E 6 - A A A N - N E E E N N
    # TODO :: Encryption Conf
    # TODO :: Firewall Conf
    # TODO :: Defender Conf
    # TODO :: OneDrive Conf
)

#endregion - Windows Configuration Profiles
#region - MacOS Configuration Profiles
#endregion - MacOS Configuration Profiles
#endregion - Device Configuration Profiles

#region - Endpoint Security Policies

# Windows - Firewall


#endregion

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

Import-Module $PSScriptRoot/../../common/Environment.psm1;
Invoke-RunMain $PSCmdlet {
    Connect-Service -Services 'Graph' -Scopes DeviceManagementServiceConfig.ReadWrite.All,deviceManagementConfiguration.ReadWrite.All, Group.ReadWrite.All;

    # Set the MDM Authority
    Invoke-Info 'Ensuring the MDM Authority is set to Intune...';
    Update-MgOrganization -OrganizationId (Get-MgOrganization | Select-Object -ExpandProperty Id) -BodyParameter (@{ mobileDeviceManagementAuthority = 1; } | ConvertTo-Json);

    # Set the Connectors
    Invoke-Info 'Setting up the Intune Connectors...';
    Invoke-MgGraphRequest -Method POST -Uri 'beta/deviceManagement/dataProcessorServiceForWindowsFeaturesOnboarding' -Body (@{
        "@odata.type" = "#microsoft.graph.dataProcessorServiceForWindowsFeaturesOnboarding";
        hasValidWindowsLicense = $True;
        areDataProcessorServiceForWindowsFeaturesEnabled = $True;
    })

    # Setup the Intune Group
    [MicrosoftGraphGroup]$Local:IntuneGroup = Get-IntuneGroup

    Invoke-Info 'Setting up Intune device compliance policies...';
    [PSCustomObject[]]$Local:DeviceCompliancePolicies = @((New-DeviceCompliancePolicy_Windows), (New-DeviceCompliancePolicy_Android), (New-DeviceCompliancePolicy_MacOS), (New-DeviceCompliancePolicy_iOS));
    $Local:DeviceCompliancePolicies | ForEach-Object {
        Invoke-Info "Setting up device compliance policy '$($_.displayName)'.";
        Set-DeviceCompliancePolicy -IntuneGroup $Local:IntuneGroup -PolicyConfiguration $_;
    }

    Invoke-Info 'Setting up Intune device configuration profiles...';
    $Script:DeviceConfigurationProfiles | ForEach-Object {
        Invoke-Info "Setting up device configuration profile '$($_.displayName)'.";
        Set-DeviceConfigurationProfile -IntuneGroup $Local:IntuneGroup -Configuration $_;
    }

    Invoke-Info 'Setting up Intune Custom Configuration Profiles...';
    # TODO :: Set up custom configuration profiles
    # $Script:

    Invoke-Info 'Setting up Intune Conditional Access Policies...';
    # TODO :: Set up conditional access policies
};
