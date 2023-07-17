#Requires -Version 5.1

Param(
    [Parameter(Mandatory = $true)]
    [String]$Client,

    [String]$SharedFolder = "AMT",
    [String]$ReportsFolder = "Monthly Report",
    [String]$ExcelFileName = "MFA Numbers.xlsx",
    [String]$ClientsFolder = "$env:USERPROFILE\$SharedFolder\Clients - Documents"
)

# Section Start - Utility Functions

<#
.SYNOPSIS
    Logs the beginning of a function and starts a timer to measure the duration.
#>
function Enter-Scope([System.Management.Automation.InvocationInfo]$Invocation) {
    $FunctionName = $Invocation.MyCommand.Name
    $script:Scope.Add($FunctionName)

    Write-Host "Entered scope $script:Scope"
}

<#
.SYNOPSIS
    Logs the end of a function and stops the timer to measure the duration.
#>
function Exit-Scope([System.Management.Automation.InvocationInfo]$Invocation) {
    Write-Host "Exited scope $script:Scope"

    $script:Scope.Remove($Invocation.MyCommand.Name) | Out-Null
}

function Scoped([System.Management.Automation.InvocationInfo]$Invocation, [ScriptBlock]$ScriptBlock) {
    Enter-Scope -Invocation $Invocation
    try {
        & $ScriptBlock
    }
    finally {
        Exit-Scope -Invocation $Invocation
    }
}

# Section End - Utility Functions



function Prompt-Confirmation {
    Param(
        [Parameter(Mandatory = $true)]
        [String]$title,

        [Parameter(Mandatory = $true)]
        [String]$question,

        [Parameter(Mandatory = $true)]
        [bool]$defaultChoice
    )
    $DefaultChoice = if ($defaultChoice) { 0 } else { 1 }
    $Result = Prompt-Selection -title $title -question $question -choices @("&Yes", "&No") -defaultChoice $defaultChoice
    switch ($Result) {
        0 { $true }
        Default { $false }
    }
}

function Prompt-Selection {
    Param(
        [Parameter(Mandatory = $true)]
        [String]$title,

        [Parameter(Mandatory = $true)]
        [String]$question,

        [Parameter(Mandatory = $true)]
        [Array]$choices,

        [Parameter(Mandatory = $true)]
        [Int]$defaultChoice
    )

    $Host.UI.RawUI.ForegroundColor = 'Yellow'
    $Host.UI.RawUI.BackgroundColor = 'Black'
    $decision = $Host.UI.PromptForChoice($title, $question, $choices, $defaultChoice)
    $Host.UI.RawUI.ForegroundColor = 'White'
    $Host.UI.RawUI.BackgroundColor = 'Black'
    return $decision
}

function Prepare {
    begin { Enter-Scope $MyInvocation }

    process {
        $global:ErrorActionPreference = "Stop"

        # Check that the script is not running as admin
        # TODO - This will probably fail is not joined to a domain
        $curUser = [Security.Principal.WindowsIdentity]::GetCurrent().name.split('\')[1]
        if ($curUser -eq 'localadmin') {
            Write-Host "Please run this script as your normal user account, not as an administrator."
            exit 1000
        }

        # Check that all required modules are installed
        foreach ($module in @('AzureAD', 'MSOnline', 'ImportExcel')) {
            if (Get-Module -ListAvailable $module -ErrorAction SilentlyContinue) {
                Write-Host "Module $module found"
            } elseif (Prompt-Confirmation "Module $module not found" "Would you like to install it now?" $true) {
                Install-Module $module -AllowClobber -Scope CurrentUser
            } else {
                Write-Host "Module $module not found; please install it using ```nInstall-Module $module -Force``"
                exit 1001
            }

            Import-Module -Name $module
        }

        $ClientFolder = Get-ChildItem "$ClientsFolder\$Client*"
        if ($ClientFolder.Count -gt 1) {
            Write-Host "Multiple client folders found; please specify the full client name."
            exit 1003
        } elseif ($ClientFolder.Count -eq 0) {
            Write-Host "Client $Client not found; please check the spelling and try again."
            exit 1003
        } else {
            $Client = $ClientFolder | Select-Object -ExpandProperty Name
        }

        # Get the first client folder that exists
        $ReportFolder = "$ClientFolder\$ReportsFolder"
        $script:ExcelFile = "$ReportFolder\$ExcelFileName"

        if ((Test-Path $ReportFolder) -eq $false) {
            Write-Host "Report folder not found; creating $ReportFolder"
            New-Item -Path $ReportFolder -ItemType Directory | Out-Null
        }

        if (Test-Path $ExcelFile) {
            Write-Host "Excel file found; creating backup $ExcelFile.bak"
            Copy-Item -Path $ExcelFile -Destination "$ExcelFile.bak" -Force
        }

        try {
            $AzureAD = Get-AzureADCurrentSessionInfo -ErrorAction Stop
            $Continue = Prompt-Confirmation "AzureAD connection found" "It looks like you are already connected to AzureAD as $($AzureAD.Account). Would you like to continue?" $true
            if ($Continue -eq $false) { throw } else { Write-Host "Continuing with existing connection" }
        } catch {
            try {
                Connect-AzureAD -ErrorAction Stop
            } catch {
                Write-Host "Failed to connect to AzureAD"
                exit 1002
            }
        }

        try {
            $CurrentCompany = Get-MsolCompanyInformation -ErrorAction Stop | Select-Object -Property DisplayName
            $Continue = Prompt-Confirmation "MSOL connection found" "It looks like you are already connected to MSOL as $($CurrentCompany.DisplayName). Would you like to continue?" $true
            if ($Continue -eq $false) { throw } else { Write-Host "Continuing with existing connection" }
        } catch {
            try {
                Connect-MsolService -ErrorAction Stop
            } catch {
                Write-Host "Failed to connect to MSOL"
                exit 1002
            }
        }
    }

    end { Exit-Scope $MyInvocation  }
}

function Get-Current {
    begin { Enter-Scope $MyInvocation }

    process {
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

    end { Exit-Scope $MyInvocation }
}

function Get-Excel {
    begin { Enter-Scope $MyInvocation }

    process {
        $import = if (Test-Path $script:ExcelFile) {
            Write-Host "Excel file found; importing data"
            Import-Excel $script:ExcelFile
        }
        else {
            Write-Host "Excel file not found; creating new file"
            New-Object -TypeName System.Collections.ArrayList
        }

        $import | Export-Excel "$script:ExcelFile" -PassThru -AutoSize -FreezeTopRowFirstColumn
    }

    end { Exit-Scope }
}

function Get-EmailToCell([OfficeOpenXml.ExcelWorksheet]$WorkSheet) {
    begin { Enter-Scope $MyInvocation }

    # TODO - Cleanup
    process {
        $Rows = $WorkSheet.Dimension.Rows
        if ($null -eq $Rows -or $Rows -lt 2) {
            Write-Host "No data found in worksheet $($WorkSheet.Name)"
            return @{}
        }

        $EmailTable = @{}
        foreach ($Index in 2..$WorkSheet.Dimension.Rows) {
            $Email = $WorkSheet.Cells[$Index, 2].Value
            $EmailTable[$Email] = $Index
        }

        $EmailTable
    }

    end { Exit-Scope $MyInvocation }
}

function Update-History([OfficeOpenXml.ExcelWorksheet]$ActiveWorkSheet, [OfficeOpenXml.ExcelWorksheet]$HistoryWorkSheet, [int]$KeepHistory = 4) {
    begin { Enter-Scope $MyInvocation }

    process {
        # This is a new worksheet, no history to update
        if ($null -eq $ActiveWorkSheet.Dimensions.Rows) {
            Write-Host "No data found in worksheet $($ActiveWorkSheet.Name)"
            return
        }

        $TotalColumns = $ActiveWorkSheet.Dimension.Columns
        $RemovedColumns = 0
        $KeptRange = ($TotalColumns - $KeepHistory)..$TotalColumns
        foreach ($ColumnIndex in 4..$ActiveWorkSheet.Dimension.Columns) {
            $WillKeep = $KeptRange -contains $ColumnIndex
            $ColumnIndex = $ColumnIndex - $RemovedColumns
            $DateValue = $ActiveWorkSheet.Cells[1, $ColumnIndex].Value

            # Empty column, remove and continue;
            if ($null -eq $DateValue -or $DateValue -eq '') {
                $ActiveWorkSheet.DeleteColumn($ColumnIndex)
                $RemovedColumns++
                continue
            }

            # This is absolutely fucking revolting
            $Date = try {
                Get-Date -Date ($DateValue)
            } catch {
                try {
                    Get-Date -Date "$($DateValue)-$(Get-Date -Format 'yyyy')"
                } catch {
                    try {
                        [DateTime]::FromOADate($DateValue)
                    } catch {
                        # Probably the check column, remove and continue;
                        $ActiveWorkSheet.DeleteColumn($ColumnIndex)
                        $RemovedColumns++
                        continue
                    }
                }
            }

            Write-Host "Processing Column $ColumnIndex which is $Date, and will keep: $WillKeep"

            if ($WillKeep -eq $true) {
                continue
            }

            if ($null -ne $HistoryWorkSheet) {
                $HistoryColumnIndex = $HistoryWorkSheet.Dimension.Columns + 1
                $HistoryWorkSheet.InsertColumn($HistoryColumnIndex, 1)
                $HistoryWorkSheet.Cells[1, $HistoryColumnIndex].Value = $Date.ToString('MMM-yy')

                $HistoryEmails = Get-EmailToCell -WorkSheet $HistoryWorkSheet
                foreach ($RowIndex in 2..$ActiveWorkSheet.Dimension.Rows) {
                    $Email = $ActiveWorkSheet.Cells[$RowIndex, 2].Value
                    $HistoryIndex = $HistoryEmails[$Email]

                    if ($null -eq $HistoryIndex) {
                        $HistoryIndex = $HistoryWorkSheet.Dimension.Rows + 1
                        $HistoryWorkSheet.InsertRow($HistoryIndex, 1)
                        $HistoryWorkSheet.Cells[$HistoryIndex, 2].Value = $Email
                    } else {
                        # Update the name and phone number
                        $HistoryWorkSheet.Cells[$HistoryIndex, 1].Value = $ActiveWorkSheet.Cells[$RowIndex, 1].Value
                        $HistoryWorkSheet.Cells[$HistoryIndex, 3].Value = $ActiveWorkSheet.Cells[$RowIndex, 3].Value
                    }

                    $HistoryWorkSheet.Cells[$HistoryIndex, $HistoryColumnIndex].Value = $ActiveWorkSheet.Cells[$RowIndex, $ColumnIndex].Value
                }
            }

            $ActiveWorkSheet.DeleteColumn($ColumnIndex)
            $RemovedColumns++
        }
    }

    end { Exit-Scope $MyInvocation }
}

function Get-ColumnDate {
    Param(
        [Parameter(Mandatory = $true)]
        [OfficeOpenXml.ExcelWorksheet]$WorkSheet,
        [Parameter(Mandatory = $true)]
        [Int32]$ColumnIndex
    )

    $DateValue = $WorkSheet.Cells[1, $ColumnIndex].Value
    try {
        Get-Date -Date ($DateValue)
    } catch {
        $Date = [DateTime]::FromOADate($DateValue)
        if ($Date.Year -eq 1899 -and $Date.Month -eq 12 -and $Date.Day -eq 30) {
            $null
        } else {
            $Date
        }
    }
}

function Prepare-Worksheet([OfficeOpenXml.ExcelWorksheet]$WorkSheet, [switch]$DuplicateCheck) {
    begin { Enter-Scope $MyInvocation }

    process {
        $Rows = $WorkSheet.Dimension.Rows
        if ($null -ne $Rows -and $Rows -ge 2) {
            # Start from 2 because the first row is the header
            $RemovedRows = 0
            $VisitiedEmails = New-Object System.Collections.Generic.List[String]
            foreach ($RowIndex in 2..$WorkSheet.Dimension.Rows) {
                $RowIndex = $RowIndex - $RemovedRows
                $Email = $WorkSheet.Cells[$RowIndex, 2].Value

                # Remove any empty rows between actual data
                if ($null -eq $Email) {
                    Write-Host "Removing row $RowIndex because email is empty."
                    $WorkSheet.DeleteRow($RowIndex)
                    $RemovedRows++
                    continue
                }

                if ($DuplicateCheck) {
                    if (!$VisitiedEmails.Contains($Email)) {
                        $VisitiedEmails.Add($Email)
                        continue
                    }

                    $ExistingIndex = $VisitiedEmails.IndexOf($Email) + 2
                    $Question = "Duplicate email found at row $RowIndex`nThe email '$Email' was first seen at row $ExistingIndex.`nPlease select which row you would like to keep, or enter 'b' to break and manually review the file."
                    $Selection = Prompt-Selection "Duplicate Email" $Question @("&Existing", "&New", "&Break") 0
                    $RemovingRow = switch ($Selection) {
                        0 { $RowIndex }
                        1 {
                            $VisitiedEmails.Remove($Email)
                            $VisitiedEmails.Add($Email)
                            $ExistingIndex
                        }
                        default {
                            Write-Host "Please manually review and remove the duplicate email that exists at rows $RowIndex and $($VisitiedEmails.IndexOf($Email) + 2)"
                            Exit 1010
                        }
                    }
                }

                $WorkSheet.DeleteRow($RemovingRow)
                $RemovedRows++
            }
        }

        $Columns = $WorkSheet.Dimension.Columns
        if ($null -ne $Columns -and $Columns -ge 4) {
            # Start from 4 because the first three columns are name,email,phone
            $RemovedColumns = 0
            foreach ($ColumnIndex in 4..$WorkSheet.Dimension.Columns) {
                $ColumnIndex = $ColumnIndex - $RemovedColumns

                # Remove any empty columns, or invalid date columns between actual data
                # TODO -> Use Get-ColumnDate
                $Value = $WorkSheet.Cells[1, $ColumnIndex].Value
                if ($null -eq $Value -or $Value -eq 'Check') {
                    Write-Host "Removing column $ColumnIndex because date is empty or invalid."
                    $WorkSheet.DeleteColumn($ColumnIndex)
                    $RemovedColumns++
                    continue
                }
            }
        }
    }

    end { Exit-Scope $MyInvocation  }
}

<#
.SYNOPSIS
    Removes all users from the worksheet which aren't present within the new data.
#>
function Remove-Users([PSCustomObject]$NewData, [OfficeOpenXml.ExcelWorksheet]$WorkSheet) {
    begin { Enter-Scope $MyInvocation }

    process {
        $EmailTable = Get-EmailToCell -WorkSheet $WorkSheet
        foreach ($Table in $EmailTable.GetEnumerator() | Sort-Object -Property Value -Descending) {
            $Email = $Table.Name
            $New = $NewData | Where-Object { $Email -eq $_.Email } | Select-Object -First 1
            if ($null -ne $New) {
                continue
            }

            $Row = $Table.Value
            Write-Host "Removing $Email from $row"
            Write-Host "Row email is $($WorkSheet.Cells[$Row, 2].Value) from $Row. (should be $Email)"
            $WorkSheet.DeleteRow($Row)
        }
    }

    end { Exit-Scope $MyInvocation  }
}

<#
.SYNOPSIS
    Updates the worksheet with the new data.
.DESCRIPTION
    This function will update the worksheet,
    Adding new users in their correct row ordered by their display name,
    and insert a new column for the current month with the correct header.
#>
function Update-Data([PSCustomObject]$NewData, [OfficeOpenXml.ExcelWorksheet]$WorkSheet, [OfficeOpenXml.ExcelWorksheet]$HistoryWorkSheet) {
    begin { Enter-Scope $MyInvocation }

    process {
        # TODO -> Check for existing column for this month
        $ColumnName = Get-Date -Format "MMM-yy"

        $ColumnIndex = $WorkSheet.Dimension.Columns + 1
        $WorkSheet.Cells[1, $ColumnIndex].Value = $ColumnName

        $EmailTable = Get-EmailToCell -WorkSheet $WorkSheet
        $HistoryEmailTable = Get-EmailToCell -WorkSheet $HistoryWorkSheet

        function Get-User {
            Param(
                [Parameter(Mandatory = $true)]
                [PSCustomObject]$EmailTable,
                [Parameter(Mandatory = $true)]
                [PSCustomObject]$Data,
                [Parameter(Mandatory = $true)]
                [OfficeOpenXml.ExcelWorksheet]$WorkSheet,
                [Parameter(Mandatory = $true)]
                [int]$LastIndex,
                [Parameter(Mandatory = $true)]
                [int]$Offset
            )

            $Row = $EmailTable[$Data.Email]
            $AddedOffset = 0
            if ($null -eq $Row) {
                $Row = $LastIndex + 1
                Write-Host "Inserting row $Row for $($Data.DisplayName)"
                $WorkSheet.InsertRow($Row, 1)
                $WorkSheet.Cells[$Row, 2].Value = $Data.Email

                $AddedOffset++
            } else {
                Write-Host "Updating row $Row with offset of ($Offset) for $($Data.DisplayName)"
                $Row = $Row + $Offset
            }

            $WorkSheet.Cells[$Row, 1].Value = $Data.DisplayName
            $WorkSheet.Cells[$Row, 3].Value = $Data.MobilePhone

            $Row,$AddedOffset
        }

        $RowOffset = 0
        $HistoryRowOffset = 0
        $LastIndex = 1
        $LastHistoryIndex = 1
        foreach ($data in $NewData) {
            ($Row, $AddingOffset) = Get-User -EmailTable $EmailTable -Data $data -WorkSheet $WorkSheet -LastIndex $LastIndex -Offset $RowOffset
            $RowOffset += $AddingOffset
            ($HistoryRow, $AddingOffset) = Get-User -EmailTable $HistoryEmailTable -Data $data -WorkSheet $HistoryWorkSheet -LastIndex $LastHistoryIndex -Offset $HistoryRowOffset
            $HistoryRowOffset += $AddingOffset

            $Cell = $WorkSheet.Cells[$Row, $ColumnIndex]
            $Cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::None
            $Cell.Value = $data.MFA_Phone
            $Cell.Style.Numberformat.Format = "@"

            $LastIndex = $Row
            $LastHistoryIndex = $HistoryRow
        }
    }

    end { Exit-Scope $MyInvocation  }
}

function Set-Check([OfficeOpenXml.ExcelWorksheet]$WorkSheet) {
    begin { Enter-Scope $MyInvocation }

    process {
        $Cells = $WorkSheet.Cells
        $lastColumn = $WorkSheet.Dimension.Columns
        $prevColumn = $lastColumn - 1
        $currColumn = $lastColumn
        $checkColumn = $lastColumn + 1

        if ($WorkSheet.Dimension.Columns -eq 4) {
            $prevColumn = $lastColumn + 2
        }

        foreach ($row in 2..$WorkSheet.Dimension.Rows) {
            $prevNumber = $Cells[$row, $prevColumn].Value
            $currNumber = $Cells[$row, $currColumn].Value
            $Cell = $Cells[$row, $checkColumn]

            ($Result, $Colour) = if ([String]::IsNullOrWhitespace($prevNumber) -and [String]::IsNullOrWhitespace($currNumber)) {
                'Missing',[System.Drawing.Color]::Turquoise
            } elseif ([String]::IsNullOrWhitespace($prevNumber)) {
                'No Previous',[System.Drawing.Color]::Yellow
            } elseif ($prevNumber -eq $currNumber) {
                'Match',[System.Drawing.Color]::Green
            } else {
                'Miss-match',[System.Drawing.Color]::Red
            }

            Write-Host "Setting cell $row,$checkColumn to $colour"

            $Cell.Value = $Result
            $Cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            $Cell.Style.Fill.BackgroundColor.SetColor(($Colour))
        }

        $Cells[1, $checkColumn].Value = 'Check'
    }

    end { Exit-Scope $MyInvocation  }
}

function Set-Styles([OfficeOpenXml.ExcelWorksheet]$WorkSheet) {
    begin { Enter-Scope $MyInvocation }

    process {
        $lastColumn = $WorkSheet.Dimension.Address -split ':' | Select-Object -Last 1
        $lastColumn = $lastColumn -replace '[0-9]', ''

        Write-Host "Last column is $lastColumn"

        Set-ExcelRange -Worksheet $WorkSheet -Range "A1:$($lastColumn)1" -Bold -HorizontalAlignment Center
        if ($WorkSheet.Dimension.Columns -ge 4) { Set-ExcelRange -Worksheet $WorkSheet -Range "D1:$($lastColumn)1" -NumberFormat "MMM-yy" }
        Set-ExcelRange -Worksheet $WorkSheet -Range "A2:$($lastColumn)$(($WorkSheet.Dimension.Rows))" -AutoSize -ResetFont -BackgroundPattern Solid
        # Set-ExcelRange -Worksheet $WorkSheet -Range "A2:$($lastColumn)$($WorkSheet.Dimension.Rows)"  # [System.Drawing.Color]::LightSlateGray
        # Set-ExcelRange -Worksheet $WorkSheet -Range "D2:$($lastColumn)$($WorkSheet.Dimension.Rows)" -NumberFormat "[<=9999999999]####-###-###;+(##) ###-###-###"
    }

    end { Exit-Scope $MyInvocation }
}

function Get-WorkSheets([OfficeOpenXml.ExcelPackage]$ExcelData) {
    begin { Enter-Scope $MyInvocation }

    process {
        $ActiveWorkSheet = $ExcelData.Workbook.Worksheets[1]
        if ($null -eq $ActiveWorkSheet) {
            $ActiveWorkSheet = $ExcelData.Workbook.Worksheets.Add("Working")
        } else { $ActiveWorkSheet.Name = "Working" }

        # New worksheet, add the columns and rows
        if ($null -eq $ActiveWorkSheet.Dimension) {
            $ActiveWorkSheet.InsertColumn(1, 3)
            $ActiveWorkSheet.InsertRow(1, 1)
        }

        $Cells = $ActiveWorkSheet.Cells
        $Cells[1, 1].Value = "Name"
        $Cells[1, 2].Value = "Email"
        $Cells[1, 3].Value = "Phone"

        $HistoryWorkSheet = $ExcelData.Workbook.Worksheets[2]
        if ($null -eq $HistoryWorkSheet -or $HistoryWorkSheet.Name -ne "History") {
            $HistoryWorkSheet = $ExcelData.Workbook.Worksheets.Copy("Working", "History")
            $HistoryWorkSheet.DeleteColumn(4, $HistoryWorkSheet.Dimension.Columns - 3)
        }

        # Move the worksheets to the correct position
        $ExcelData.Workbook.Worksheets.MoveToStart("Working")
        $ExcelData.Workbook.Worksheets.MoveAfter("History", "Working")

        return $ActiveWorkSheet, $HistoryWorkSheet
    }

    end { Exit-Scope $MyInvocation  }
}

function Save-Excel([OfficeOpenXml.ExcelPackage]$ExcelData) {
    begin { Enter-Scope $MyInvocation }

    process {
        if ($ExcelData.Workbook.Worksheets.Count -gt 2) {
            Write-Host "Removing $($ExcelData.Workbook.Worksheets.Count - 2) worksheets"
            foreach ($Index in 3..$ExcelData.Workbook.Worksheets.Count) {
                $ExcelData.Workbook.Worksheets.Delete(3)
            }
        }

        Close-ExcelPackage $ExcelData -Show # -SaveAs "$ExcelFile"
    }

    end { Exit-Scope $MyInvocation }
}

function Main {
    begin {
        $script:Scope = New-Object System.Collections.Generic.List[String]
        Enter-Scope $MyInvocation
    }

    process {
        Prepare

        $NewData = Get-Current
        $ExcelData = Get-Excel

        ($ActiveWorkSheet, $HistoryWorkSheet) = Get-WorkSheets -ExcelData $ExcelData
        Prepare-Worksheet -WorkSheet $ActiveWorkSheet -DuplicateCheck
        Prepare-Worksheet -WorkSheet $HistoryWorkSheet

        Update-History -HistoryWorkSheet $HistoryWorkSheet -ActiveWorkSheet $ActiveWorkSheet
        Remove-Users -NewData $NewData -WorkSheet $ActiveWorkSheet
        Update-Data -NewData $NewData -WorkSheet $ActiveWorkSheet -HistoryWorkSheet $HistoryWorkSheet
        Set-Check -WorkSheet $ActiveWorkSheet

        @($ActiveWorkSheet, $HistoryWorkSheet) | ForEach-Object { Set-Styles -WorkSheet $_ }

        Save-Excel -ExcelData $ExcelData
    }

    end { Exit-Scope $MyInvocation }
}

Main
