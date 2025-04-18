#Requires -Version 5.1

Using module ..\..\common\Environment.psm1
Using module ..\..\common\Logging.psm1
Using module ..\..\common\Connection.psm1

Using module ExchangeOnlineManagement

[CmdletBinding()]
param()

[String]$Script:RetentionPolicy = 'Log Retention Policy';
[String]$Script:RetentionPolicyDescription = 'One year retention policy for all activities';
[String]$Script:RetentionPolicyDuration = 'TwelveMonths';
[String[]]$Script:RentionPolicyRecordTypes = @('ExchangeAdmin', 'ExchangeItem', 'ExchangeItemGroup', 'SharePoint', 'SyntheticProbe', 'SharePointFileOperation', 'OneDrive', 'AzureActiveDirectory', 'AzureActiveDirectoryAccountLogon', 'DataCenterSecurityCmdlet', 'ComplianceDLPSharePoint', 'Sway', 'ComplianceDLPExchange', 'SharePointSharingOperation', 'AzureActiveDirectoryStsLogon', 'SkypeForBusinessPSTNUsage', 'SkypeForBusinessUsersBlocked', 'SecurityComplianceCenterEOPCmdlet', 'ExchangeAggregatedOperation', 'PowerBIAudit', 'CRM', 'Yammer', 'SkypeForBusinessCmdlets', 'Discovery', 'MicrosoftTeams', 'ThreatIntelligence', 'MailSubmission', 'MicrosoftFlow', 'AeD', 'MicrosoftStream', 'ComplianceDLPSharePointClassification', 'ThreatFinder', 'Project', 'SharePointListOperation', 'SharePointCommentOperation', 'DataGovernance', 'Kaizala', 'SecurityComplianceAlerts', 'ThreatIntelligenceUrl', 'SecurityComplianceInsights', 'MIPLabel', 'WorkplaceAnalytics', 'PowerAppsApp', 'PowerAppsPlan', 'ThreatIntelligenceAtpContent', 'LabelContentExplorer', 'TeamsHealthcare', 'ExchangeItemAggregated', 'HygieneEvent', 'DataInsightsRestApiAudit', 'InformationBarrierPolicyApplication', 'SharePointListItemOperation', 'SharePointContentTypeOperation', 'SharePointFieldOperation', 'MicrosoftTeamsAdmin', 'HRSignal', 'MicrosoftTeamsDevice', 'MicrosoftTeamsAnalytics', 'InformationWorkerProtection', 'Campaign', 'DLPEndpoint', 'AirInvestigation', 'Quarantine', 'MicrosoftForms', 'ApplicationAudit', 'ComplianceSupervisionExchange', 'CustomerKeyServiceEncryption', 'OfficeNative', 'MipAutoLabelSharePointItem', 'MipAutoLabelSharePointPolicyLocation', 'MicrosoftTeamsShifts', 'SecureScore', 'MipAutoLabelExchangeItem', 'CortanaBriefing', 'Search', 'WDATPAlerts', 'PowerPlatformAdminDlp', 'PowerPlatformAdminEnvironment', 'MDATPAudit', 'SensitivityLabelPolicyMatch', 'SensitivityLabelAction', 'SensitivityLabeledFileAction', 'AttackSim', 'AirManualInvestigation', 'SecurityComplianceRBAC', 'UserTraining', 'AirAdminActionInvestigation', 'MSTIC', 'PhysicalBadgingSignal', 'TeamsEasyApprovals', 'AipDiscover', 'AipSensitivityLabelAction', 'AipProtectionAction', 'AipFileDeleted', 'AipHeartBeat', 'MCASAlerts', 'OnPremisesFileShareScannerDlp', 'OnPremisesSharePointScannerDlp', 'ExchangeSearch', 'SharePointSearch', 'PrivacyDataMinimization', 'LabelAnalyticsAggregate', 'MyAnalyticsSettings', 'SecurityComplianceUserChange', 'ComplianceDLPExchangeClassification', 'ComplianceDLPEndpoint', 'MipExactDataMatch', 'MSDEResponseActions', 'MSDEGeneralSettings', 'MSDEIndicatorsSettings', 'MS365DCustomDetection', 'MSDERolesSettings', 'MAPGAlerts', 'MAPGPolicy', 'MAPGRemediation', 'PrivacyRemediationAction', 'PrivacyDigestEmail', 'MipAutoLabelSimulationProgress', 'MipAutoLabelSimulationCompletion', 'MipAutoLabelProgressFeedback', 'DlpSensitiveInformationType', 'MipAutoLabelSimulationStatistics', 'LargeContentMetadata', 'Microsoft365Group', 'CDPMlInferencingResult', 'FilteringMailMetadata', 'CDPClassificationMailItem', 'CDPClassificationDocument', 'OfficeScriptsRunAction', 'FilteringPostMailDeliveryAction', 'CDPUnifiedFeedback', 'TenantAllowBlockList', 'ConsumptionResource', 'HealthcareSignal', 'DlpImportResult', 'CDPCompliancePolicyExecution', 'MultiStageDisposition', 'PrivacyDataMatch', 'FilteringDocMetadata', 'FilteringEmailFeatures', 'PowerBIDlp', 'FilteringUrlInfo', 'FilteringAttachmentInfo', 'CoreReportingSettings', 'ComplianceConnector', 'PowerPlatformLockboxResourceAccessRequest', 'PowerPlatformLockboxResourceCommand', 'CDPPredictiveCodingLabel', 'CDPCompliancePolicyUserFeedback', 'WebpageActivityEndpoint', 'OMEPortal', 'CMImprovementActionChange', 'FilteringUrlClick', 'MipLabelAnalyticsAuditRecord', 'FilteringEntityEvent', 'FilteringRuleHits', 'FilteringMailSubmission', 'LabelExplorer', 'MicrosoftManagedServicePlatform', 'PowerPlatformServiceActivity', 'ScorePlatformGenericAuditRecord', 'FilteringTimeTravelDocMetadata', 'Alert', 'AlertStatus', 'AlertIncident', 'IncidentStatus', 'Case', 'CaseInvestigation', 'RecordsManagement', 'PrivacyRemediation', 'DataShareOperation', 'CdpDlpSensitive', 'EHRConnector', 'FilteringMailGradingResult', 'PublicFolder', 'PrivacyTenantAuditHistoryRecord', 'AipScannerDiscoverEvent', 'EduDataLakeDownloadOperation', 'M365ComplianceConnector', 'MicrosoftGraphDataConnectOperation', 'MicrosoftPurview', 'FilteringEmailContentFeatures', 'PowerPagesSite', 'PowerAppsResource', 'PlannerPlan', 'PlannerCopyPlan', 'PlannerTask', 'PlannerRoster', 'PlannerPlanList', 'PlannerTaskList', 'PlannerTenantSettings', 'ProjectForTheWebProject', 'ProjectForTheWebTask', 'ProjectForTheWebRoadmap', 'ProjectForTheWebRoadmapItem', 'ProjectForTheWebProjectSettings', 'ProjectForTheWebRoadmapSettings', 'QuarantineMetadata', 'MicrosoftTodoAudit', 'TimeTravelFilteringDocMetadata', 'TeamsQuarantineMetadata', 'SharePointAppPermissionOperation', 'MicrosoftTeamsSensitivityLabelAction', 'FilteringTeamsMetadata', 'FilteringTeamsUrlInfo', 'FilteringTeamsPostDeliveryAction', 'MDCAssessments', 'MDCRegulatoryComplianceStandards', 'MDCRegulatoryComplianceControls', 'MDCRegulatoryComplianceAssessments', 'MDCSecurityConnectors', 'MDADataSecuritySignal', 'VivaGoals', 'FilteringRuntimeInfo', 'AttackSimAdmin', 'MicrosoftGraphDataConnectConsent', 'FilteringAtpDetonationInfo', 'PrivacyPortal', 'ManagedTenants', 'UnifiedSimulationMatchedItem', 'UnifiedSimulationSummary', 'UpdateQuarantineMetadata', 'MS365DSuppressionRule', 'PurviewDataMapOperation', 'FilteringUrlPostClickAction', 'IrmUserDefinedDetectionSignal', 'TeamsUpdates', 'PlannerRosterSensitivityLabel', 'MS365DIncident', 'FilteringDelistingMetadata', 'ComplianceDLPSharePointClassificationExtended', 'MicrosoftDefenderForIdentityAudit', 'SupervisoryReviewDayXInsight', 'DefenderExpertsforXDRAdmin', 'CDPEdgeBlockedMessage', 'HostedRpa', 'CdpContentExplorerAggregateRecord', 'CDPHygieneAttachmentInfo', 'CDPHygieneSummary', 'CDPPostMailDeliveryAction', 'CDPEmailFeatures', 'CDPHygieneUrlInfo', 'CDPUrlClick', 'CDPPackageManagerHygieneEvent', 'FilteringDocScan', 'TimeTravelFilteringDocScan', 'MAPGOnboard', 'VfamCreatePolicy', 'VfamUpdatePolicy', 'VfamDeletePolicy', 'M365DAAD', 'CdpColdCrawlStatus', 'PowerPlatformAdministratorActivity', 'Windows365CustomerLockbox', 'CdpResourceScopeChangeEvent');

Invoke-RunMain $PSCmdlet {
    Connect-Service -Service SecurityComplience;

    $Local:UnifiedAuditLogRetentionPolicy = Get-UnifiedAuditLogRetentionPolicy | Where-Object { $_.Name -eq $Script:RetentionPolicy };

    $UnifiedAuditLogRetentionPolicy = Get-UnifiedAuditLogRetentionPolicy | Where-Object { $_.Name -eq $Script:RetentionPolicy };
    if ($null -eq $UnifiedAuditLogRetentionPolicy) {
        Invoke-Info 'Creating new policy...';

        New-UnifiedAuditLogRetentionPolicy `
            -Name $Script:RetentionPolicy `
            -Description $Script:RetentionPolicyDescription `
            -RetentionDuration $Script:RetentionPolicyDuration `
            -Priority 10 `
            -RecordTypes $Script:RentionPolicyRecordTypes;
        return;
    }

    Invoke-Info 'Updating existing policy...';
    Set-UnifiedAuditLogRetentionPolicy `
        -Identity $UnifiedAuditLogRetentionPolicy.Identity `
        -Description $Script:RetentionPolicyDescription `
        -RetentionDuration $Script:RetentionPolicyDuration `
        -Priority 10 `
        -RecordTypes $Script:RentionPolicyRecordTypes;
}
