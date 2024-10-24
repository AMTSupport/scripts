#Requires -Modules ExchangeOnlineManagement

Using module ../../common/Environment.psm1
Using module ../../common/Logging.psm1
Using module ../../common/Scope.psm1
Using module ../../common/Input.psm1
Using module ../../common/Connection.psm1
Using module ../Common.psm1

[CmdletBinding()]
Param(
    [Parameter(Mandatory)]
    [ValidateSet('MailBox', 'Policies', 'Outlook')]
    [String[]]$Update
)

#region - Mailbox settings
function Enable-MailboxAuditing {
    Set-OrganizationConfig -AuditDisabled $false
    Get-Mailbox | ForEach-Object { Set-Mailbox -AuditEnabled $true -Identity $_.WindowsEmailAddress }
}

function Enable-MailTips {
    Set-OrganizationConfig -MailTipsAllTipsEnabled $true -MailTipsExternalRecipientsTipsEnabled $true -MailTipsGroupMetricsEnabled $true -MailTipsLargeAudienceThreshold '25'
}

function Enable-AlertSpamPolicyAdmin {
    $AlertsUser = Get-AlertsUser;

    Set-HostedOutboundSpamFilterPolicy -Identity Default `
        -BccSuspiciousOutboundAdditionalRecipients @($AlertsUser) `
        -BccSuspiciousOutboundMail $true `
        -NotifyOutboundSpam $true `
        -NotifyOutboundSpamRecipients @($AlertsUser);
}
#endregion - Mailbox settings

#region - Outlook settings
function Disable-OutlookStorageProviders {
    Set-OwaMailboxPolicy -Identity OwaMailboxPolicy-Default -AdditionalStorageProvidersAvailable $false
}
#endregion

#region - Policies

function Update-SafeAttachmentsPolicy {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope; }

    process {
        $Local:Params = @{
            Name          = 'AMT - Default safe attachments'
            Enable        = $true

            Action        = 'DynamicDelivery'
            QuarantineTag = 'AdminOnlyAccessPolicy'
        };

        try {
            Get-SafeAttachmentPolicy -Identity $Local:Params.Name -ErrorAction Stop | Out-Null;
            Invoke-Info 'Default SafeAttachments Policy already exists. Updating...';
            Set-SafeAttachmentPolicy @Local:Params;
        } catch {
            Invoke-Info 'Default SafeAttachments Policy does not exist. Creating...';
            New-SafeAttachmentPolicy @Local:Params | Out-Null;
        }

        try {
            $Local:Rule = Get-SafeAttachmentRule -Identity $Local:Params.Name -ErrorAction Stop;

            if ($Local:Rule.SafeAttachmentPolicy -ne $Local:Params.Name) {
                Invoke-Info 'Default SafeAttachments Rule exists but is not linked to the policy. Updating...';
                Set-SafeAttachmentRule -Identity $Local:Params.Name -SafeAttachmentPolicy $Local:Params.Name;
            }

            $Local:Domain = Get-AcceptedDomain;
            if (-not ($Local:Domain | Where-Object { $Local:Rule.RecipientDomainIs -contains $_ }).Count -eq $Local:Domain.Count) {
                Invoke-Info 'Default SafeAttachments Rule exists but is not linked to the accepted domain. Updating...';
                Set-SafeAttachmentRule -Identity $Local:Params.Name -RecipientDomainIs $Local:Domain.Name;
            }

            if ($Local:Rule.Priority -ne 0) {
                Invoke-Info 'Default SafeAttachments Rule exists but is not priority 0. Updating...';
                Set-SafeAttachmentRule -Identity $Local:Params.Name -Priority 0;
            }
        } catch {
            Invoke-Info 'Default SafeAttachments Rule does not exist. Creating...';
            New-SafeAttachmentRule -Name $Local:Params.Name -SafeAttachmentPolicy $Local:Params.Name -RecipientDomainIs (Get-AcceptedDomain).Name -Priority 0 | Out-Null;
        }
    }
}

function Update-SafeLinksPolicy {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope; }

    process {
        $Local:Params = @{
            Name                     = 'AMT - Default safe links'
            AllowClickThrough        = $false
            DeliverMessageAfterScan  = $true
            DisableUrlRewrite        = $false
            EnableForInternalSenders = $true
            EnableSafeLinksForEmail  = $true
            EnableSafeLinksForOffice = $true
            EnableSafeLinksForTeams  = $true
            ScanUrls                 = $true
            TrackClicks              = $true
        };

        try {
            Get-SafeLinksPolicy -Identity $Local:Params.Identity -ErrorAction Stop | Out-Null;
            Invoke-Info 'Default SafeLinks Policy already exists. Updating...';
            Set-SafeLinksPolicy @Local:Params;
        } catch {
            Invoke-Info 'Default SafeLinks Policy does not exist. Creating...';
            New-SafeLinksPolicy @Local:Params | Out-Null;
        }

        try {
            $Local:Rule = Get-SafeLinksRule -Identity $Local:Params.Name -ErrorAction Stop;

            if ($Local:Rule.SafeLinksPolicy -ne $Local:Params.Name) {
                Invoke-Info 'Default SafeLinks Rule exists but is not linked to the policy. Updating...';
                Set-SafeLinksRule -Identity $Local:Params.Name -SafeLinksPolicy $Local:Params.Name;
            }

            $Local:Domain = Get-AcceptedDomain;
            if (-not ($Local:Domain | Where-Object { $Local:Rule.RecipientDomainIs -contains $_ }).Count.Equals($Local:Domain.Count)) {
                Invoke-Info 'Default SafeLinks Rule exists but is not linked to the accepted domain. Updating...';
                Set-SafeLinksRule -Identity $Local:Params.Name -RecipientDomainIs $Local:Domain.Name;
            }

            if ($Local:Rule.Priority -ne 0) {
                Invoke-Info 'Default SafeLinks Rule exists but is not priority 0. Updating...';
                Set-SafeLinksRule -Identity $Local:Params.Name -Priority 0;
            }
        } catch {
            Invoke-Info 'Default SafeLinks Rule does not exist. Creating...';
            New-SafeLinksRule -Name $Local:Params.Name -SafeLinksPolicy $Local:Params.Name -RecipientDomainIs (Get-AcceptedDomain).Name -Priority 0 | Out-Null;
        }
    }
}

function Update-AntiPhishPolicy {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope; }

    process {
        $Local:Params = @{
            Identity                            = 'AMT - Default phishing filter policy'

            DmarcQuarantineAction               = 'Quarantine'
            DmarcRejectAction                   = 'Reject'

            EnableSpoofIntelligence             = $true
            SpoofQuarantineTag                  = 'AdminOnlyAccessPolicy'

            EnableMailboxIntelligenceProtection = $true
            MailboxIntelligenceProtectionAction = 'Quarantine'
            MailboxIntelligenceQuarantineTag    = 'AdminOnlyAccessPolicy'

            EnableTargetedDomainsProtection     = $true
            EnableOrganizationDomainsProtection = $true
            TargetedDomainProtectionAction      = 'Quarantine'
            TargetedDomainQuarantineTag         = 'AdminOnlyAccessPolicy'

            EnableTargetedUserProtection        = $true
            TargetedUserProtectionAction        = 'Quarantine'
            TargetedUsersToProtect              = (Get-Mailbox | ForEach-Object { "$($_.Name);$($_.WindowsEmailAddress)" })
            TargetedUserQuarantineTag           = 'AdminOnlyAccessPolicy'

            EnableFirstContactSafetyTips        = $true
            EnableMailboxIntelligence           = $true
            EnableSimilarDomainsSafetyTips      = $true
            EnableSimilarUsersSafetyTips        = $true
            EnableUnauthenticatedSender         = $true
            EnableUnusualCharactersSafetyTips   = $true
            EnableViaTag                        = $true

            HonorDmarcPolicy                    = $true
            PhishThresholdLevel                 = 3

        };

        if (Get-AntiPhishPolicy -Identity $Local:Params.Identity -ErrorAction SilentlyContinue) {
            Invoke-Info 'Default AntiPhish Policy already exists. Updating...';
            Set-AntiPhishPolicy @Local:Params;
        } else {
            Invoke-Info 'Default AntiPhish Policy does not exist. Creating...';
            New-AntiPhishPolicy @Local:Params;
        }

        $Local:Rule = Get-AntiPhishRule -Identity $Local:Params.Identity -ErrorAction Stop;
        if (-not $Local:Rule) {
            Invoke-Info 'Default AntiPhish Rule does not exist. Creating...';
            New-AntiPhishRule -Name $Local:Params.Identity -AntiPhishPolicy $Local:Params.Identity -RecipientDomainIs (Get-AcceptedDomain).Name -Priority 0;
        } else {
            if ($Local:Rule.AntiPhishPolicy -ne $Local:Params.Identity) {
                Invoke-Info 'Default AntiPhish Rule exists but is not linked to the policy. Updating...';
                Set-AntiPhishRule -Identity $Local:Params.Identity -AntiPhishPolicy $Local:Params.Identity;
            }

            $Local:Domain = Get-AcceptedDomain;
            if (-not ($Local:Domain | Where-Object { $Local:Rule.RecipientDomainIs -contains $_ }).Count.Equals($Local:Domain.Count)) {
                Invoke-Info 'Default AntiPhish Rule exists but is not linked to the accepted domain. Updating...';
                Set-AntiPhishRule -Identity $Local:Params.Identity -RecipientDomainIs $Local:Domain.Identity;
            }

            if ($Local:Rule.Priority -ne 0) {
                Invoke-Info 'Default AntiPhish Rule exists but is not priority 0. Updating...';
                Set-AntiPhishRule -Identity $Local:Params.Identity -Priority 0;
            }
        }
    }
}

function Update-AntiMalwarePolicy {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope; }

    process {
        $Local:Params = @{
            Name                                                  = 'AMT - Default malware filter policy'
            Enable                                                = $true
            Action                                                = 'Quarantine'
            HighConfidenceSpamAction                              = 'Quarantine'
            HighConfidenceMalwareAction                           = 'Quarantine'
            BulkSpamAction                                        = 'Quarantine'
            BulkMalwareAction                                     = 'Quarantine'
            SpamAction                                            = 'Quarantine'
            PhishAction                                           = 'Quarantine'
            ZAPEnabled                                            = $true
            BypassInboundMessages                                 = $false
            BypassOutboundMessages                                = $false
            BypassUnauthenticatedSenders                          = $false
            BypassAuthenticatedUsers                              = $false
            BypassMessagesSentToAndFromFollowedUsers              = $false
            BypassMessagesSentToFollowedUsers                     = $false
            BypassMalwareDetection                                = $false
            BypassSpamDetection                                   = $false
            BypassInboxRules                                      = $false
            BypassSecurityGroupManagerModeration                  = $false
            BypassModerationFromRecipient                         = $false
            BypassSenderAdminCheck                                = $false
            BypassSenderInRecipientBlockedCondition               = $false
            BypassSenderInRecipientBlockedConditionExceptions     = @()
            BypassSenderInRecipientBlockedConditionAction         = 'Quarantine'
            BypassMalwareFiltering                                = $false
            BypassSpamFiltering                                   = $false
            BypassRBLCheck                                        = $false
            BypassZeroHourExploits                                = $false
            BypassSpoofDetection                                  = $false
            BypassPhishingDetection                               = $false
            BypassDirectoryBasedEdgeBlocking                      = $false
            BypassSenderReputationCheck                           = $false
            BypassSenderInRecipientBlockedConditionFallbackAction = 'Quarantine'
            BypassMaliciousFileDetection                          = $false
            BypassDomainSecureEnabledCheck                        = $false
            BypassDomainSecureOverrideCheck                       = $false
            BypassDomainSecureOverrideAction                      = 'Quarantine'
            BypassDomainSecureOverrideBulkAction                  = 'Quarantine'
            BypassDomainSecureOverrideHighConfidenceAction        = 'Quarantine'
        }

        try {
            Get-SafeLinksPolicy -Identity $Local:Params.Identity -ErrorAction Stop | Out-Null;
            Invoke-Info 'Default SafeLinks Policy already exists. Updating...';
            Set-SafeLinksPolicy @Local:Params;
        } catch {
            Invoke-Info 'Default SafeLinks Policy does not exist. Creating...';
            New-SafeLinksPolicy @Local:Params | Out-Null;
        }

        try {
            $Local:Rule = Get-SafeLinksRule -Identity $Local:Params.Name -ErrorAction Stop;

            if ($Local:Rule.SafeLinksPolicy -ne $Local:Params.Name) {
                Invoke-Info 'Default SafeLinks Rule exists but is not linked to the policy. Updating...';
                Set-SafeLinksRule -Identity $Local:Params.Name -SafeLinksPolicy $Local:Params.Name;
            }

            $Local:Domain = Get-AcceptedDomain;
            if (-not ($Local:Domain | Where-Object { $Local:Rule.RecipientDomainIs -contains $_ }).Count.Equals($Local:Domain.Count)) {
                Invoke-Info 'Default SafeLinks Rule exists but is not linked to the accepted domain. Updating...';
                Set-SafeLinksRule -Identity $Local:Params.Name -RecipientDomainIs $Local:Domain.Name;
            }

            if ($Local:Rule.Priority -ne 0) {
                Invoke-Info 'Default SafeLinks Rule exists but is not priority 0. Updating...';
                Set-SafeLinksRule -Identity $Local:Params.Name -Priority 0;
            }
        } catch {
            Invoke-Info 'Default SafeLinks Rule does not exist. Creating...';
            New-SafeLinksRule -Name $Local:Params.Name -SafeLinksPolicy $Local:Params.Name -RecipientDomainIs (Get-AcceptedDomain).Name -Priority 0 | Out-Null;
        }
    }
}

#endregion - Policies

Invoke-RunMain $PSCmdlet {
    Connect-Service -Service ExchangeOnline;

    foreach ($Local:Item in $Update) {
        Invoke-Info "Updating $Local:Item settings...";

        switch ($Local:Item) {
            'MailBox' {
                Enable-MailboxAuditing;
                Enable-MailTips;
            }
            'Policies' {
                Update-AntiPhishPolicy;
                # Update-SafeAttachmentsPolicy;
                # Update-SafeLinksPolicy;
            }
            'Outlook' {
                Disable-OutlookStorageProviders;
            }
        }
    }
};
