#Requires -Version 5.1

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

Param(
    [Parameter()]
    [String]$ApiKey = "",

    [Parameter()]
    [String]$Endpoint = ""
)

#region - Scope Functions

function Enter-Scope([System.Management.Automation.InvocationInfo]$Invocation) {
    $Params = $Invocation.BoundParameters
    Write-Verbose "Entered scope $($Invocation.MyCommand.Name) with parameters [$($Params.Keys) = $($Params.Values)]"
}

function Exit-Scope([System.Management.Automation.InvocationInfo]$Invocation, [Object]$ReturnValue) {
    Write-Verbose "Exited scope $($Invocation.MyCommand.Name) with return value [$ReturnValue]"
}

#endregion Scope Functions

#region - Script Functions

#region - Excel Functions

function Get-Excel {
    begin { Enter-Scope $MyInvocation }

    process {
        $Excel = [OfficeOpenXml.ExcelPackage]::new()

        $WorkSheet = $Excel.Workbook.Worksheets.Add("Main")
        $WorkSheet.InsertColumn(1, 1)
        $WorkSheet.InsertRow(1, 1)
        $WorkSheet.Cells[1, 1].Value = "Company"

        return $Excel
    }

    end { Exit-Scope $MyInvocation $Excel }
}

function Set-Companies([OfficeOpenXml.ExcelWorksheet]$WorkSheet, [String[]]$Companies) {
    begin { Enter-Scope $MyInvocation }

    process {
        for ($Index = 0; $Index -lt $Companies.Count; $Index++) {
            $RowIndex = $Index + 2;

            Write-Host "Setting company $($Companies[$Index]) at row $RowIndex"
            $WorkSheet.Cells[$RowIndex, 1].Value = ($Companies[$Index])
        }
    }

    end { Exit-Scope $MyInvocation }
}

function Set-Style([OfficeOpenXml.ExcelWorksheet]$WorkSheet) {
    begin { Enter-Scope $MyInvocation }

    process {
        $lastColumn = $WorkSheet.Dimension.Address -split ':' | Select-Object -Last 1
        $lastColumn = $lastColumn -replace '[0-9]', ''

        Set-ExcelRange -Worksheet $WorkSheet -Range $WorkSheet.Dimension.Address -AutoSize
        Set-ExcelRange -Worksheet $WorkSheet -Range "A1:$($lastColumn)1" -Bold -HorizontalAlignment Center
    }

    end { Exit-Scope $MyInvocation }
}

function Save-Excel([OfficeOpenXml.ExcelPackage]$ExcelData) {
    begin { Enter-Scope $MyInvocation }

    process { Close-ExcelPackage $ExcelData -Show -SaveAs "$env:TEMP\Companies.xlsx" }

    end { Exit-Scope $MyInvocation }
}

#endregion - Excel Functions

#region - Hudu Functions

function Get-Companies {
    begin { Enter-Scope $MyInvocation }

    process {
        $Companies = ((Invoke-WebRequest -Headers @{"x-api-key" = $ApiKey} -Uri "https://$Endpoint/api/v1/companies?page_size=1000").Content) | ConvertFrom-Json
        $Companies = $Companies.companies | Select-Object -ExpandProperty name | Sort-Object
        $Companies
    }

    end { Exit-Scope $MyInvocation $Companies }
}

#endregion - Hudu Functions

#region - Main

function Prepare {
    begin { Enter-Scope $MyInvocation }

    process {
        # Check that the script is not running as admin
        # TODO - This will probably fail is not joined to a domain
        $curUser = [Security.Principal.WindowsIdentity]::GetCurrent().name.split('\')[1]
        if ($curUser -eq 'localadmin') {
            Write-Error "Please run this script as your normal user account, not as an administrator."
            exit 1000
        }

        # Check that all required modules are installed
        foreach ($module in @('ImportExcel')) {
            if (-not (Get-Module -ListAvailable $module -ErrorAction SilentlyContinue)) {
                Write-Host "Module $module not found, installing..."
                Install-Module -Name $module -AllowClobber -Scope CurrentUser
            }

            Import-Module -Name $module
        }
    }

    end { Exit-Scope $MyInvocation }
}

function Main() {
    begin { Enter-Scope $MyInvocation }

    process {
        Prepare
        $Excel = Get-Excel
        $Companies = Get-Companies
        $WorkSheet = $Excel.Workbook.Worksheets["Main"]

        Set-Companies -WorkSheet $WorkSheet -Companies $Companies
        Set-Style -WorkSheet $WorkSheet
        Save-Excel $Excel
    }

    end { Exit-Scope $MyInvocation }
}

Main

#endregion - Main
