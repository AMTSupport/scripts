[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Update')]
Param(
    [Parameter(ParameterSetName = 'Update')]
    [String]$Endpoint,

    [Parameter(ParameterSetName = 'Update')]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [String]$Database = '.',

    [Parameter(ParameterSetName = 'Invoke', Mandatory)]
    [ScriptBlock]$Invoke
)

function New-HuduDatabase {
    Param(
        [Parameter(Mandatory)]
        [String]$Database,

        [Parameter(Mandatory)]
        [String]$Endpoint
    )

    $Local:Companies = async {
        Get-HuduCompanies -Endpoint $Endpoint;
    };
    $Local:BitWardenItems = async {
        bw list items --search 'O365 Admin -' | ConvertFrom-Json;
    };

    $Local:Companies = $Local:Companies | await;
    $Local:BitwardenItems = $Local:BitWardenItems | await;

    $Local:DisplayItems = $Local:BitwardenItems `
        | Select-Object -Property name, id `
        | Sort-Object -Property name;

    [HashTable]$Local:Matches = @{};
    foreach ($Local:Company in $Local:Companies) {
        $Local:Selection = Get-UserSelection `
            -Title "Select Bitwarden item for $($Local:Company.name)" `
            -Question "Which Bitwarden item corresponds to $($Local:Company.name)?" `
            -Items $Local:DisplayItems `
            -AllowNone `
            -FormatChoice { $Input.name };

        if (-not $Local:Selection) {
            Invoke-Warn "No selection made for $($Local:Company.name); skipping.";
            continue;
        }

        $Local:Matches[$Local:Company.name]['BitWarden'] = $Local:Selection.id;
    }

    $Local:Matches | ConvertTo-Json | Out-File -FilePath "$Database";
}

Import-Module $PSScriptRoot/../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    Invoke-EnsureModule -Modules "$PSScriptRoot/Common.psm1";

    if ($PSCmdlet.ParameterSetName -eq 'Update') {
        Invoke-Info "Updating companies"

        if (-not $Endpoint) {
            $Endpoint = Get-UserInput -Title 'Hudu Endpoint' -Question 'Please enter your Hudu Endpoint';
        }

        if (-not $Database) {
            $Database = Get-UserInput -Title 'Database Path' -Question 'Please enter the path to save the database';
        }

        # TODO :: Create update function if there is an existing file.
        New-HuduDatabase -Database "$Database/matched-companies.json" -Endpoint $Endpoint;
    } else {
        Invoke-Info "Invoking existing companies";

        # Invoke-EnsureModule -Modules "$PSScriptRoot/Existing.psm1";
        # Invoke-Existing-Company -Database $Database;
    }
};
