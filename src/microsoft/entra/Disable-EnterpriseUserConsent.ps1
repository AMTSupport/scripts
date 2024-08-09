Using module ../../common/Environment.psm1
Using module ../../common/Connect.psm1
Using module Microsoft.Graph.Identity.SignIns

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

Invoke-RunMain $PSCmdlet {

};
