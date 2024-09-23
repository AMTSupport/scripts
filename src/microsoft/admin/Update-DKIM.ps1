#Requires -Version 7.1

Using module ../../common/Environment.psm1
Using module ../../common/Connection.psm1
Using module ../../common/Logging.psm1

Using module Microsoft.Graph.Identity.DirectoryManagement

Using namespace Microsoft.Graph.PowerShell.Models

# foreach ($domain in $domains) {
#     # Get the domain name
#     $domainName = $domain.Name

#     # Update DKIM records
#     New-DkimSigningConfig -DomainName $domainName -Enabled $true

#     # Verify DKIM records
#     $dkimConfig = Get-DkimSigningConfig -Identity $domainName

#     if ($dkimConfig.Status -eq "Enabled") {
#         Write-Output "DKIM is enabled for $domainName"
#     } else {
#         Write-Output "Failed to enable DKIM for $domainName"
#     }
# }

Invoke-RunMain $PSCmdlet {
    Connect-Service -Services @('Graph') -Scopes @('Domain.ReadWrite.All');

    [MicrosoftGraphDomain]$Local:AllDomains = Get-MgDomain;
    [MicrosoftGraphDomain]$Local:RootDomain = $Local:AllDomains | Where-Object { $_.IsInitial -eq $true };
    [MicrosoftGraphDomain]$Local:CustomDomains = $Local:AllDomains | Where-Object { $_.IsInitial -eq $false -and $_.IsVerified -eq $true };

    New-MgDomainServiceConfigurationRecord `
        -DomainName $Local:RootDomain.Id `
        -RecordType 'CNAME' `
        -RecordData 'selector1._domainkey' `
        -RecordValue 'selector1-<GUID>._domainkey.<DOMAIN>' `
        -Ttl 3600;

    $Local:CustomDomains | ForEach-Object {
        [MicrosoftGraphDomain]$Local:CustomDomain = $_;
        Invoke-Info "Updating DKIM for $($Local:CustomDomain.Id)...";

        $Local:ExistingRecord = $Local:CustomDomain

        # [MicrosoftGraphDomain]$Local:DKIM = New-MgDomainDkimSigningConfig -DomainName $Local:CustomDomain.Id -Enabled $true;

        if ($Local:DKIM.Status -eq 'Enabled') {
            Invoke-Info "DKIM is enabled for $($Local:CustomDomain.Id).";
        } else {
            Invoke-Error "Failed to enable DKIM for $($Local:CustomDomain.Id).";
        }
    }
};
