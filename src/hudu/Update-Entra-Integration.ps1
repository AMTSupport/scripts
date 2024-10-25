#Requires -Version 7.1

Using module ../common/Environment.psm1
Using module ../common/Logging.psm1
Using module ../common/Input.psm1
Using module ../common/Utils.psm1

[CmdletBinding()]
Param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Company,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Endpoint = "hudu.amt.com.au"
)

function Get-Expiration([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$ApiKey) {
    $Local:Companies = Invoke-WebRequest -Headers @{ "x-api-key" = $ApiKey } -Uri "https://$Endpoint/api/v1/companies?page_size=1000" | ConvertFrom-Json;
    $Local:CompanyData = $Local:Companies | Where-Object { $_.name -like $Company -or $_.name -like $Company };

    if (-not $Local:CompanyData) {
        Write-Error -Message "Company $Company not found" -Category ObjectNotFound;
    }
}

function Update-Expiration {

}

function New-SecretValue {

}

function Remove-OldSecrets {

}

Invoke-RunMain $PSCmdlet {
    [String]$Local:HuduKey = Get-VarOrSave -VariableName 'HUDU_KEY' -LazyValue {
        $Local:Input = Get-UserInput -Title 'Hudu API Key' -Question 'Please enter your Hudu API Key';
        if (-not $Local:Input) {
            throw 'Hudu Key cannot be empty';
        }

        return $Local:Input;
    };
}
