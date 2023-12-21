function Get-Companies {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [String]$Endpoint,

        [Parameter(Mandatory)]
        [String]$ApiKey,

        [Parameter()]
        [switch]$OnlyParents
    )

    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation $Local:Companies; }

    process {
        [String]$Local:Uri = "https://$Endpoint/api/v1/companies?page_size=1000";
        [PSCustomObject]$Local:Headers = @{'x-api-key' = $ApiKey };

        try {
            $Local:Response = (Invoke-WebRequest -Headers $Local:Headers -Uri $Local:Uri -UseBasicParsing);
            [PSCustomObject[]]$Local:Companies = ($Local:Response | ConvertFrom-Json).companies;

            Invoke-Debug "Got $($Local:Companies.Count) companies from hudu.";
        } catch {
            Invoke-Error -Message 'Failed to get companies from hudu; Check your API Key.';
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        }

        [Object[]]$Local:Companies = $Local:Companies `
            | Select-Object -Property name, company_type, parent_company_name `
            | Sort-Object -Property name `
            | Where-Object { $_.company_type -ne 'Supplier' -and (-not $OnlyParents -or ($null -eq $_.parent_company_name)) };

        return $Local:Companies;
    }
}

Export-ModuleMember -Function Get-Companies;
