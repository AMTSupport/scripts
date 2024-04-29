<#
.SYNOPSIS
    Update all links for users in passwords.

.DESCRIPTION
    This will collect a list of all the user cards from O365,
    and try to link them to the correct password card and any other related cards.
#>

[CmdletBinding()]
param()

function Update-Links {
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory)]
        [String]$UserCardId,

        [Parameter(Mandatory)]
        [PSCustomObject[]]$PasswordCards
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        Invoke-Info "Updating links for user card $UserCardId";

        $MatchingPasswordCard = $PasswordCards | Where-Object {
            $_.
        }
    }
}

function Get-Passwords {
    param(
        [Parameter(Mandatory)]
        [String]$Endpoint,

        [Parameter(Mandatory)]
        [String]$CompanyId
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $Private:Request = Invoke-HuduRequest -Endpoint:$Endpoint -Path:'passwords' -Method:GET -Params:@('page_size=1000', "company_id=$CompanyId");
        [PSCustomObject]$Private:Passwords = $Private:Request.asset_passwords;

        return $Private:Passwords;
    }

}

Import-Module $PSScriptRoot/../src/common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    [PSCustomObject]$Private:Companies = Get-HuduCompanies -Endpoint:$Private:Endpoint;

    foreach ($Private:Company in $Private:Companies) {
        [PSCustomObject[]]$Private:Passwords = Get-Passwords -Endpoint:$Private:Endpoint -CompanyId:$Private:Company.id;
        [PSCustomObject[]]$Private:UserCards = Get-UserCards -Endpoint:$Private:Endpoint -CompanyId:$Private:Company.id;

        $Private:UserCards | ForEach-Object {
            Update-Links -UserCardId:$_.id -PasswordCards:$Private:Passwords;
        }
    }
};
