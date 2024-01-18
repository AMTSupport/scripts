[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Invoke')]
Param(
    [Parameter(ParameterSetName = 'Update', Mandatory)]
    [String]$Endpoint,

    [Parameter(ParameterSetName = 'Update', Mandatory)]
    [String]$ApiKey,

    [Parameter(ParameterSetName = 'Update')]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [String]$Database = '.',

    [Parameter(ParameterSetName = 'Invoke', Mandatory)]
    [ScriptBlock]$Invoke
)


function New-Database {
    Param(
        [Parameter(Mandatory)]
        [String]$Database,

        [Parameter(Mandatory)]
        [String]$Endpoint,

        [Parameter(Mandatory)]
        [String]$ApiKey
    )

    $Local:Companies = Get-HuduCompanies -Endpoint $Endpoint -ApiKey $ApiKey;
    $Local:BitwardenItems = bw list items --search 'O365 Admin -';

    $Local:DisplayItems = $Local:BitwardenItems `
        | Select-Object -Property name, id `
        | Sort-Object -Property name;

    [HashTable]$Local:Matches = @{};
    foreach ($Local:Company in $Local:Companies) {
        $Local:Selection = Get-PopupSelection -Title "Select Bitwarden item for $($Local:Company.name)" -Items $Local:DisplayItems -AllowNone;
        if (-not $Local:Selection) {
            Invoke-Warn "No selection made for $($Local:Company.name); skipping.";
            continue;
        }

        $Local:Matches[$Local:Company.name] = $Local:Selection.id;
    }

    $Local:Matches | ConvertTo-Json | Out-File -FilePath "$Database";
}

Import-Module $PSScriptRoot/../common/Environment.psm1;
Invoke-RunMain $MyInvocation {
    Invoke-EnsureModules -Modules "$PSScriptRoot/Common.psm1";

    if ($PSCmdlet.ParameterSetName -eq 'Update') {
        Invoke-Info "Updating companies"
        # TODO :: Create update function if there is an existing file.
        New-Database -Database "$Database/matched-companies.json" -Endpoint $Endpoint -ApiKey $ApiKey;
    } else {
        Invoke-Info "Invoking existing companies";

        # Invoke-EnsureModules -Modules "$PSScriptRoot/Existing.psm1";
        # Invoke-Existing-Company -Database $Database;
    }
};
