function Get-HuduApiKey {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [String]$Local:HuduKey = Get-VarOrSave -VariableName 'HUDU_API_KEY' -LazyValue {
            [SecureString]$Local:UserInput = Get-UserInput `
                -Title 'Hudu API Key' `
                -Question 'Please enter your Hudu API Key' `
                -AsSecureString -Validate { $_ -and $_.Length -eq 24; };

            return $Local:UserInput | ConvertFrom-SecureString;
        };

        [SecureString]$Local:SecureStringKey = $Local:HuduKey | ConvertTo-SecureString;
        return $Local:SecureStringKey | ConvertFrom-SecureString -AsPlainText;
    }
}

function Get-HuduCompanies {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [String]$Endpoint,

        [Parameter()]
        [Switch]$OnlyParents
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue ($Local:Companies | ForEach-Object { $_.name }); }

    process {
        [String]$Local:Uri = "https://$Endpoint/api/v1/companies?page_size=1000";
        [PSCustomObject]$Local:Headers = @{'x-api-key' = Get-HuduApiKey };

        try {
            $Local:Response = (Invoke-WebRequest -Headers $Local:Headers -Uri $Local:Uri -UseBasicParsing);
            [PSCustomObject[]]$Local:Companies = ($Local:Response | ConvertFrom-Json).companies;

            Invoke-Debug "Got $($Local:Companies.Count) companies from hudu.";
        } catch {
            Invoke-Error 'Failed to get companies from hudu; Check your API Key.';
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        }

        [Object[]]$Local:Companies = $Local:Companies `
            | Select-Object -Property name, company_type, parent_company_name `
            | Sort-Object -Property name `
            | Where-Object { $_.company_type -ne 'Supplier' -and (-not $OnlyParents -or ($null -eq $_.parent_company_name)) };

        return $Local:Companies;
    }
}

Export-ModuleMember -Function Get-HuduCompanies;
