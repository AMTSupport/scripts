#Requires -Version 5.1

using namespace OfficeOpenXml;

<#
.SYNOPSIS
    A Utility to create an excel spreadsheet filled with companies from hudu.
.DESCRIPTION
    A Utility to create an excel spreadsheet filled with companies from hudu.
    These companies will be filled under the column named Company in the first row of a sheet named Main.
    The script will also set the style of the sheet to be bold and centered.
    The script will save the excel file to the temp directory and open it.
.PARAMETER ApiKey
    The API key to use to connect to hudu.
    This is a required parameter.
.PARAMETER Endpoint
    The hudu endpoint to connect to, this is only the domain name, not the full url.
    This is a required parameter.
#>

[CmdletBinding()]
Param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$ApiKey = "",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$Endpoint = "",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [String]$OutputPath = "$env:TEMP"
)

#region - Excel Functions

function New-ExcelPackage {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Excel; }

    process {
        [ExcelPackage]$Local:Excel = [ExcelPackage]::new();
        [ExcelWorksheet]$Local:WorkSheet = $Local:Excel.Workbook.Worksheets.Add("Main");

        $Local:WorkSheet.InsertColumn(1, 1);
        $Local:WorkSheet.InsertRow(1, 1);
        $Local:WorkSheet.Cells[1, 1].Value = "Company";
        $Local:WorkSheet.Cells[1, 2].Value = "Type";

        return $Local:Excel;
    }
}

function Set-Companies(
    [Parameter(Mandatory)]
    [ExcelWorksheet]$WorkSheet,
    [Parameter(Mandatory)]
    [PSCustomObject[]]$Companies
) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        Invoke-Info "Adding $($Companies.Count) companies to excel sheet...";

        for ($Local:Index = 0; $Local:Index -lt $Companies.Count; $Local:Index++) {
            [Int16]$Local:RowIndex = $Index + 2;

            Invoke-Debug "Setting company $($Companies[$Local:Index]) at row $Local:RowIndex";
            $WorkSheet.Cells[$Local:RowIndex, 1].Value = ($Companies[$Local:Index].name)
            $WorkSheet.Cells[$Local:RowIndex, 2].Value = ($Companies[$Local:Index].company_type)
        }
    }
}

function Set-Style(
    [Parameter(Mandatory)]
    [ExcelWorksheet]$WorkSheet
) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [String]$Local:LastColumn = $WorkSheet.Dimension.Address -split ':' | Select-Object -Last 1;
        [String]$Local:LastColumn = $Local:LastColumn -replace '[0-9]', '';

        Set-ExcelRange -Worksheet $WorkSheet -Range $WorkSheet.Dimension.Address -AutoSize
        Set-ExcelRange -Worksheet $WorkSheet -Range "A1:$($Local:LastColumn)1" -Bold -HorizontalAlignment Center
    }
}

#endregion - Excel Functions

Import-Module $PSScriptRoot/../common/Environment.psm1;
Invoke-RunMain $PSCmdlet {
    Invoke-EnsureUser;
    Invoke-EnsureModule -Modules 'ImportExcel', "$PSScriptRoot\Common.psm1"; # TODO - This should be imported by compiler in future.

    [ExcelPackage]$Local:Excel = New-ExcelPackage;
    [PSCustomObject[]]$Local:Companies = Get-HuduCompanies -Endpoint $Endpoint -OnlyParents;
    [ExcelWorksheet]$Local:WorkSheet = $Local:Excel.Workbook.Worksheets["Main"];

    Set-Companies -WorkSheet $Local:WorkSheet -Companies $Local:Companies;
    Set-Style -WorkSheet $Local:WorkSheet;

    $Local:OutputLocation = Join-Path -Path $OutputPath -ChildPath "Companies.xlsx";
    Close-ExcelPackage $Local:Excel -Show -SaveAs $Local:OutputLocation;
};
