function Disable-EnterpriseConsent_UserConsent {
    Connect-Service Graph -Scopes 'Policy.ReadWrite.Authorization';

    [HashTable]$Private:Body = @{
        "permissionGrantPolicyIdsAssignedToDefaultUserRole" = @(
            "managePermissionGrantsForOwnedResource.{other-current-policies}"
        )
    };

    Update-MgPolicyAuthorizationPolicy -AuthorizationPolicyId authorizationPolicy -BodyParameter:$Private:Body;
}

function Set-EnterpriseConsent_ForwardRequestsToAlerts {

}

Import-Module $PSScriptRoot/../../common/Environment.psm1;
Invoke-RunMain $PSCmdlet {

};
