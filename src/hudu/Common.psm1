Using module ../common/Logging.psm1
Using module ../common/Scope.psm1
Using module ../common/Input.psm1
Using module ../common/Exit.psm1
Using module ../common/Utils.psm1

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

function Invoke-HuduRequest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [String]$Endpoint,

        [Parameter(Mandatory)]
        [String]$Path,

        [Parameter()]
        [String[]]$Params,

        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
        [String]$Method,

        [Parameter()]
        [String]$Body
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Response; }

    process {
        [String]$Private:Uri = "https://${Endpoint}/api/v1/${Path}?$(if ($Params) { $Params -join '&' })";
        [PSCustomObject]$Private:Headers = @{
            'x-api-key' = Get-HuduApiKey;
            'Content-Type' = 'application/json';
        };

        [HashTable]$Local:Arguments = @{
            Headers = $Private:Headers;
            Uri = $Private:Uri;
            Method = $Method;
        };

        if ($Body && $Method -in @('POST', 'PUT')) {
            $Local:Arguments.Body = $Body;
        }

        Invoke-Verbose "Invoking hudu request to $Private:Uri with method $Method";

        try {
            $Local:Response = Invoke-RestMethod @Local:Arguments;
        } catch {
            Invoke-Error 'Failed to get response from hudu; Check your API Key.';
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        }

        return $Local:Response;
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
        $Private:Response = Invoke-HuduRequest -Endpoint:$Endpoint -Path:'companies' -Method:GET -Params:@('page_size=1000');
        [PSCustomObject[]]$Local:Companies = $Private:Response.companies;

        Invoke-Debug "Got $($Local:Companies.Count) companies from hudu.";

        [Object[]]$Local:Companies = $Local:Companies `
            | Sort-Object -Property name `
            | Where-Object { ($_.company_type -ne 'Supplier' -and $_.company_type -ne 'Personal') -and (-not $OnlyParents -or ($null -eq $_.parent_company_name)) };

        return $Local:Companies;
    }
}

Export-ModuleMember -Function Invoke-HuduRequest, Get-HuduCompanies;
