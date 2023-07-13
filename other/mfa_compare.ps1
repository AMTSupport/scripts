Param(
    [Parameter(Mandatory = $true)]
    [String]$Client,

    [String]$ClientsFolder = "$env:USERPROFILE\APPLIED MARKETING TECHNOLOGIES\Clients - Documents"
)

function PromptForConfirmation {
    Param(
        [Parameter(Mandatory = $true)]
        [String]$title,

        [Parameter(Mandatory = $true)]
        [String]$question,

        [Parameter(Mandatory = $true)]
        [Int]$defaultChoice
    )

    $Host.UI.RawUI.ForegroundColor = 'Yellow'
    $Host.UI.RawUI.BackgroundColor = 'Black'
    $decision = $Host.UI.PromptForChoice($title, $question, @("&Yes", "&No"), $defaultChoice)
    if ($decision -eq 0) {
        $Host.UI.RawUI.ForegroundColor = 'White'
        $Host.UI.RawUI.BackgroundColor = 'Black'
        return $true
    } else {
        $Host.UI.RawUI.ForegroundColor = 'White'
        $Host.UI.RawUI.BackgroundColor = 'Black'
        return $false
    }
}

function Prepare {
    # Check that all required modules are installed
    foreach ($module in @('AzureAD', 'MSOnline', 'ImportExcel')) {
        if (Get-Module -ListAvailable $module -ErrorAction SilentlyContinue) {
            Write-Host "Module $module found"
        } elseif (PromptForConfirmation "Module $module not found" "Would you like to install it now?" 1) {
            Install-Module $module -AllowClobber -Scope CurrentUser
        } else {
            Write-Host "Module $module not found; please install it using ```nInstall-Module $module -Force``"
            exit 1001
        }

        Import-Module -Name $module
    }

    try {
        Connect-AzureAD -ErrorAction Stop
        Connect-MsolService -ErrorAction Stop
    } catch {
        Write-Host "Failed to connect to AzureAD or MSOL Service"
        exit 1002
    }

    $ClientFolder = "$ClientsFolder\$Client"
    $ReportFolder = "$ClientFolder\Monthly Report"
    $script:ExcelFile = "$ReportFolder\MFA Numbers.xlsx"
    
    if ((Test-Path $ClientFolder) -eq $false) {
        Write-Host "Client $Client not found; please check the spelling and try again."
        exit 1003
    }

    if ((Test-Path $ReportFolder) -eq $false) {
        Write-Host "Report folder not found; creating $ReportFolder"
        New-Item -Path $ReportFolder -ItemType Directory | Out-Null
    }

    if (Test-Path $ExcelFile) {
        Write-Host "Excel file found; creating backup $ExcelFile.bak"
        Copy-Item -Path $ExcelFile -Destination "$ExcelFile.bak" -Force
    }
}

function Get-Current {
    Get-MsolUser -All `
        | Where-Object { $_.isLicensed -eq $true } `
        | Sort-Object DisplayName `
        | Select-Object DisplayName,@{ N = 'Email'; E = { $_.UserPrincipalName } },MobilePhone,MFA_Phone,MFA_Email `
        | ForEach-Object {
            $expanded = Get-MsolUser -UserPrincipalName $_.Email | Select-Object -ExpandProperty StrongAuthenticationUserDetails
            $_.MFA_Email = $expanded.Email
            $_.MFA_Phone = $expanded.PhoneNumber
            $_
        }
}

function Get-Excel {
    $import = Import-Excel $script:ExcelFile

    $ExcelData = $import | Export-Excel $script:ExcelFile -PassThru -AutoSize -FreezeTopRowFirstColumn

    $ExcelData
}

function Get-EmailToCell {
    Param(
        [Parameter(Mandatory = $true)]
        [OfficeOpenXml.ExcelPackage]$ExcelData
    )
    
    $EmailTable = @{}
    $Cells = $ExcelData.Sheet1.Cells
    $RemovedRows = 0
    foreach ($Index in 2..$ExcelData.Sheet1.Dimension.Rows) {
        $Index = $Index - $RemovedRows
        $Email = $Cells[$Index, 2].Value
        
        # Remove any empty rows between actual data
        if ($null -eq $Email) {
            $ExcelData.Sheet1.DeleteRow($Index)
            $RemovedRows++
            continue
        }

        $EmailTable[$Email] = $index
    }

    $EmailTable
}

function Prune-Users {
    Param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$NewData,
        [Parameter(Mandatory = $true)]
        [OfficeOpenXml.ExcelPackage]$ExcelData
    )

    Write-Host "Starting Function $($MyInvocation.MyCommand.Name)"

    $EmailTable = Get-EmailToCell -ExcelData $ExcelData

    foreach ($Email in $EmailTable.Keys) {
        $Row = $EmailTable[$Email]
        $New = $NewData | Where-Object { $Email -eq $_.Email } -ErrorAction Stop

        if ($null -eq $New) {
            $ExcelData.Sheet1.DeleteRow($Row)
            continue
        }
    }

    Write-Host "Ending Function $($MyInvocation.MyCommand.Name)"
}

function Update-Data {
    Param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$NewData,
        [Parameter(Mandatory = $true)]
        [OfficeOpenXml.ExcelPackage]$ExcelData
    )
    Write-Host "Starting Function $($MyInvocation.MyCommand.Name)"

    # TODO -> Check for existing column for this month
    $ColumnName = (Get-Date).ToString("dd/MM/yyyy")

    $WorkSheet = $ExcelData.Sheet1
    $Cells = $WorkSheet.Cells
    $Cells[1, $ExcelData.Sheet1.Dimension.Columns].Value = $ColumnName

    $EmailTable = Get-EmailToCell -ExcelData $ExcelData

    $RowOffset = 0
    $LastIndex = $null
    foreach ($data in $NewData) {
        $Row = $EmailTable[$data.Email]

        if ($null -eq $Row) {
            $Row = if ($null -eq $LastIndex) { 2 } else { $LastIndex + 1 }
            
            $ExcelData.Sheet1.InsertRow($Row, 1)
            $ExcelData.Sheet1.Cells[$Row, 1].Value = $data.DisplayName
            $ExcelData.Sheet1.Cells[$Row, 2].Value = $data.Email
            $ExcelData.Sheet1.Cells[$Row, 3].Value = $data.MobilePhone

            $RowOffset++
        } else {
            $Row = $Row + $RowOffset
        }

        $Cell = $Cells[$Row, $ExcelData.Sheet1.Dimension.Columns]
        $Cell.Value = $data.MFA_Phone
        $Cell.Style.Numberformat.Format = "@"
        $LastIndex = $Row        
    }

    Write-Host "Ending Function $($MyInvocation.MyCommand.Name)"
}

function Set-Check {
    Param(
        [Parameter(Mandatory = $true)]
        [OfficeOpenXml.ExcelPackage]$ExcelData
    )
    Write-Host "Starting Function $($MyInvocation.MyCommand.Name)"

    $Cells = $ExcelData.Sheet1.Cells
    $lastColumn = $ExcelData.Sheet1.Dimension.Columns
    $prevColumn = $lastColumn - 1
    $currColumn = $lastColumn
    $checkColumn = $lastColumn + 1
    foreach ($row in 2..$ExcelData.Sheet1.Dimension.Rows) {
        $prevNumber = $Cells[$row, $prevColumn].Value
        $currNumber = $Cells[$row, $currColumn].Value

        $checkCell = $Cells[$row, $checkColumn]
        $checkCell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
        if ($null -eq $prevNumber) {
            $checkCell.Value = 'No Previous'
            $checkCell.Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::Yellow)
        } elseif ($currNumber -ne $prevNumber) {
            $checkCell.Value = 'Miss-match'
            $checkCell.Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::Red)
        } else {
            $checkCell.Value = 'Match'
            $checkCell.Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::Green)
        }
    }

    $Cells[1, $checkColumn].Value = 'Check'

    Write-Host "Ending Function $($MyInvocation.MyCommand.Name)"
}

function Set-Styles {
    Param(
        [Parameter(Mandatory = $true)]
        [OfficeOpenXml.ExcelPackage]$ExcelData
    )
    Write-Host "Starting Function $($MyInvocation.MyCommand.Name)"

    $lastColumn = $ExcelData.Sheet1.Dimension.Address -split ':' | Select-Object -Last 1
    $lastColumn = $lastColumn -replace '[0-9]', ''

    Set-ExcelRange -Worksheet $ExcelData.Sheet1 -Range "A1:$($lastColumn)1" -Bold -HorizontalAlignment Center
    Set-ExcelRange -Worksheet $ExcelData.Sheet1 -Range "D1:$($lastColumn)1" -NumberFormat "MMM-yy"
    Set-ExcelRange -Worksheet $ExcelData.Sheet1 -Range "A1:$($lastColumn)$($ExcelData.Sheet1.Dimension.Rows)" -AutoSize
    # Set-ExcelRange -Worksheet $ExcelData.Sheet1 -Range "D2:$($lastColumn)$($ExcelData.Sheet1.Dimension.Rows)" -NumberFormat "[<=9999999999]####-###-###;+(##) ###-###-###"

    Write-Host "Ending Function $($MyInvocation.MyCommand.Name)"
}

function Save-Excel {
    Param(
        [Parameter(Mandatory = $true)]
        [OfficeOpenXml.ExcelPackage]$ExcelData
    )

    Close-ExcelPackage $ExcelData -Show
}

function Main {
    Prepare

    $NewData = Get-Current
    $ExcelData = Get-Excel

    Prune-Users -NewData $NewData -ExcelData $ExcelData
    Update-Data -NewData $NewData -ExcelData $ExcelData
    Set-Check -ExcelData $ExcelData
    Set-Styles -ExcelData $ExcelData
    Save-Excel -ExcelData $ExcelData
}

Main



