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

Import-Module $PSScriptRoot/../../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {

};
