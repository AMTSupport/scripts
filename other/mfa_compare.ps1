#Requires -Version 5.1

Param(
    [Parameter(Mandatory = $true)]
    [String]$Client,

    [String]$SharedFolder = "AMT",
    [String]$ReportsFolder = "Monthly Report",
    [String]$ExcelFileName = "MFA Numbers.xlsx",
    [String]$ClientsFolder = "$env:USERPROFILE\$SharedFolder\Clients - Documents"
)

#region - Error Codes

$Script:NULL_ARGUMENT = 1000;
$Script:FAILED_EXPECTED_VALUE = 1004;

#endregion - Error Codes

#region - Utility Functions

function Assert-NotNull([Parameter(Mandatory, ValueFromPipeline)][Object]$Object, [String]$Message) {
    if ($null -eq $Object -or $Object -eq '') {
        if ($null -eq $Message) {
            Write-Host -ForegroundColor Red -Object 'Object is null';
            Invoke-FailedExit -ExitCode $Script:NULL_ARGUMENT;
        } else {
            Write-Host -ForegroundColor Red -Object $Message;
            Invoke-FailedExit -ExitCode $Script:NULL_ARGUMENT;
        }
    }
}

function Assert-Equals([Parameter(Mandatory, ValueFromPipeline)][Object]$Object, [Parameter(Mandatory)][Object]$Expected, [String]$Message) {
    if ($Object -ne $Expected) {
        if ($null -eq $Message) {
            Write-Host -ForegroundColor Red -Object "Object [$Object] does not equal expected value [$Expected]";
            Invoke-FailedExit -ExitCode $Script:FAILED_EXPECTED_VALUE;
        } else {
            Write-Host -ForegroundColor Red -Object $Message;
            Invoke-FailedExit -ExitCode $Script:FAILED_EXPECTED_VALUE;
        }
    }
}

function Get-ScopeFormatted([Parameter(Mandatory)][System.Management.Automation.InvocationInfo]$Invocation) {
    $Invocation | Assert-NotNull -Message 'Invocation was null';

    [String]$ScopeName = $Invocation.MyCommand.Name;
    [String]$ScopeName = if ($null -ne $ScopeName) { "Scope: $ScopeName" } else { 'Scope: Unknown' };
    $ScopeName
}

function Enter-Scope([Parameter(Mandatory)][System.Management.Automation.InvocationInfo]$Invocation) {
    $Invocation | Assert-NotNull -Message 'Invocation was null';

    [String]$Local:ScopeName = Get-ScopeFormatted -Invocation $Invocation;
    $Local:Params = $Invocation.BoundParameters
    if ($null -ne $Params -and $Params.Count -gt 0) {
        [String[]]$ParamsFormatted = $Params.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" };
        if ($PSVersionTable.PSVersion.Major -ge 6 -and $PSVersionTable.PSVersion.Minor -ge 2) {
            $Local:ParamsFormatted = $Local:ParamsFormatted | Join-String -Separator "`n`t";
        } else {
            $Local:ParamsFormatted = $Split -join "`n`t";
        }

        $Local:ParamsFormatted = "Parameters: $Local:ParamsFormatted";
    } else {
        [String]$Local:ParamsFormatted = 'Parameters: None';
    }

    Write-Verbose "Entered Scope`n`t$ScopeName`n`t$ParamsFormatted";
}

function Exit-Scope([Parameter(Mandatory)][System.Management.Automation.InvocationInfo]$Invocation, [Object]$ReturnValue) {
    $Invocation | Assert-NotNull -Message 'Invocation was null';

    [String]$Local:ScopeName = Get-ScopeFormatted -Invocation $Invocation;
    [String]$Local:ReturnValueFormatted = if ($null -ne $ReturnValue) {
        [String]$Local:FormattedValue = switch ($ReturnValue) {
            { $_ -is [System.Collections.Hashtable] } { "`n`t$(([HashTable]$ReturnValue).GetEnumerator().ForEach({ "$($_.Key) = $($_.Value)" }) -join "`n`t")" }
            default { $ReturnValue }
        }

        "Return Value: $Local:FormattedValue"
    } else { 'Return Value: None' };

    Write-Verbose "Exited Scope`n`t$ScopeName`n`t$ReturnValueFormatted";
}

function Get-PromptInput {
    Param(
        [Parameter(Mandatory = $true)]
        [String]$title,

        [Parameter(Mandatory = $true)]
        [String]$question
    )

    $Host.UI.RawUI.ForegroundColor = 'Yellow'
    $Host.UI.RawUI.BackgroundColor = 'Black'

    Write-Host $title
    Write-Host "$($question): " -NoNewline

    $Host.UI.RawUI.FlushInputBuffer();
    $userInput = $Host.UI.ReadLine()

    $Host.UI.RawUI.ForegroundColor = 'White'
    $Host.UI.RawUI.BackgroundColor = 'Black'
    return $userInput
}

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
    $Result = Prompt-Selection -title $title -question $question -choices @('&Yes', '&No') -defaultChoice $defaultChoice
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

function Import-DownloadableModule([String]$Name) {
    begin { Enter-Scope $MyInvocation }

    process {
        $Module = Get-Module -ListAvailable | Where-Object { $_.Name -eq $Name }
        if ($null -eq $Module) {
            Write-Host "Downloading module $Name..."
            Install-PackageProvider -Name NuGet -Confirm:$false
            Install-Module -Name $Name -Scope CurrentUser -Confirm:$false -Force
            $Module = Get-Module -ListAvailable | Where-Object { $_.Name -eq $Name }
        }

        Import-Module $Module
    }

    end { Exit-Scope $MyInvocation }
}

function Invoke-FailedExit([Parameter(Mandatory)][ValidateNotNullOrEmpty()][Int]$ExitCode, [System.Management.Automation.ErrorRecord]$ErrorRecord) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        If ($null -ne $ErrorRecord) {
            [System.Management.Automation.InvocationInfo]$Local:InvocationInfo = $ErrorRecord.InvocationInfo;
            $Local:InvocationInfo | Assert-NotNull -Message 'Invocation info was null, how am i meant to find error now??';

            [System.Exception]$Local:RootCause = $ErrorRecord.Exception;
            while ($null -ne $Local:RootCause.InnerException) {
                $Local:RootCause = $Local:RootCause.InnerException;
            }

            Write-Host -ForegroundColor Red $Local:InvocationInfo.PositionMessage;
            Write-Host -ForegroundColor Red $Local:RootCause.Message;
        }

        Exit $ExitCode;
    }
}

function Invoke-QuickExit {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        Remove-RunningFlag;

        Write-Host -ForegroundColor Red 'Exiting...';
        Exit 0;
    }
}

#endregion - Utility Functions

# Section Start - Main Functions

function Invoke-SetupEnvironment {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        $ErrorActionPreference = "Stop";

        # Check that the script is not running as admin
        # TODO - This will probably fail is not joined to a domain
        $curUser = [Security.Principal.WindowsIdentity]::GetCurrent().name.split('\')[1]
        if ($curUser -eq 'localadmin') {
            Write-Error "Please run this script as your normal user account, not as an administrator."
            exit 1000
        }

        # Check that all required modules are installed
        foreach ($module in @('AzureAD', 'MSOnline', 'ImportExcel')) {
            if (Get-Module -ListAvailable $module -ErrorAction SilentlyContinue) {
                Write-Host -ForegroundColor Cyan "Module $module found"
            } elseif (Prompt-Confirmation "Module $module not found" "Would you like to install it now?" $true) {
                Install-Module $module -AllowClobber -Scope CurrentUser
            } else {
                Write-Error "Module $module not found; please install it using ```nInstall-Module $module -Force``"
                exit 1001
            }

            Import-Module -Name $module
        }

        $ClientFolder = Get-ChildItem "$ClientsFolder\$Client*"
        if ($ClientFolder.Count -gt 1) {
            Write-Error "Multiple client folders found; please specify the full client name."
            exit 1003
        } elseif ($ClientFolder.Count -eq 0) {
            Write-Error "Client $Client not found; please check the spelling and try again."
            exit 1003
        } else {
            $Client = $ClientFolder | Select-Object -ExpandProperty Name
        }

        # Get the first client folder that exists
        $ReportFolder = "$ClientFolder\$ReportsFolder"
        $script:ExcelFile = "$ReportFolder\$ExcelFileName"

        if ((Test-Path $ReportFolder) -eq $false) {
            Write-Host -ForegroundColor Cyan "Report folder not found; creating $ReportFolder"
            New-Item -Path $ReportFolder -ItemType Directory | Out-Null
        }

        if (Test-Path $ExcelFile) {
            Write-Host -ForegroundColor Cyan "Excel file found; creating backup $ExcelFile.bak"
            Copy-Item -Path $ExcelFile -Destination "$ExcelFile.bak" -Force
        }

        try {
            $AzureAD = Get-AzureADCurrentSessionInfo -ErrorAction Stop
            $Continue = Prompt-Confirmation "AzureAD connection found" "It looks like you are already connected to AzureAD as $($AzureAD.Account). Would you like to continue?" $true
            if ($Continue -eq $false) { throw } else { Write-Host -ForegroundColor Cyan "Continuing with existing connection" }
        } catch {
            try {
                Connect-AzureAD -ErrorAction Stop
            } catch {
                Write-Error "Failed to connect to AzureAD"
                exit 1002
            }
        }

        try {
            $CurrentCompany = Get-MsolCompanyInformation -ErrorAction Stop | Select-Object -Property DisplayName
            $Continue = Prompt-Confirmation "MSOL connection found" "It looks like you are already connected to MSOL as $($CurrentCompany.DisplayName). Would you like to continue?" $true
            if ($Continue -eq $false) { throw } else { Write-Host -ForegroundColor Cyan "Continuing with existing connection" }
        } catch {
            try {
                Connect-MsolService -ErrorAction Stop
            } catch {
                Write-Error "Failed to connect to MSOL"
                exit 1002
            }
        }
    }
}

<#
.SYNOPSIS
Get the up to date online data from MSOL for user auth methods.

.NOTES
The returned data is a PSCustomObject with the following properties:
    DisplayName
    Email
    MobilePhone
    MFA_App
    MFA_Email
    MFA_Phone

It is ordered by DisplayName.
#>
function Get-CurrentData {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:ExpandedUsers; }

    process {
        [Object[]]$Local:LicensedUsers = Get-MsolUser -All | Where-Object { $_.isLicensed -eq $true } | Sort-Object DisplayName;
        [PSCustomObject[]]$Local:ExpandedUsers = $Local:LicensedUsers `
            | Select-Object `
                DisplayName, `
                @{ N = 'Email'; E = { $_.UserPrincipalName } }, `
                MobilePhone, `
                @{ N = 'MFA_App'; E = { $_.StringAuthenticationPhoneAppDetails }  }, `
                @{ N = 'MFA_Email'; E = { $_.StrongAuthenticationUserDetails.Email } }, `
                @{ N = 'MFA_Phone'; E = { $_.StrongAuthenticationUserDetails.PhoneNumber } };

        return $Local:ExpandedUsers;
    }
}

function Get-Excel {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        $import = if (Test-Path $script:ExcelFile) {
            Write-Host -ForegroundColor Cyan "Excel file found; importing data"
            try {
                Import-Excel $script:ExcelFile
            } catch {
                Write-Error "Failed to import Excel file."

                $Message = $_.Exception.Message
                $WriteMessage = switch -Regex ($Message) {
                    "Duplicate column headers" {
                        $Match = Select-String "Duplicate column headers found on row '(?<row>[0-9]+)' in columns '(?:(?<column>[0-9]+)(?:[ ]?))+'." -InputObject $_
                        $Row = $Match.Matches.Groups[1].Captures
                        $Columns = $Match.Matches.Groups[2].Captures
                        "There were duplicate columns found on row $Row in columns $($Columns -join ", "); Please remove any duplicate columns and try again"
                    }
                    default { "Unknown error; Please examine the error message and try again" }
                }
                Write-Error $WriteMessage

                exit 1004
            }
        } else {
            Write-Host -ForegroundColor Cyan "Excel file not found; creating new file"
            New-Object -TypeName System.Collections.ArrayList
        }

        $import | Export-Excel "$script:ExcelFile" -PassThru -AutoSize -FreezeTopRowFirstColumn
    }
}

function Get-EmailToCell([Parameter(Mandatory)][ValidateNotNullOrEmpty()][OfficeOpenXml.ExcelWorksheet]$WorkSheet) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:EmailTable; }

    process {
        Trap {
            Write-Host -ForegroundColor Red "Unexpected error occurred while getting email to cell mapping";
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        };

        [Int]$Local:SheetRows = $WorkSheet.Dimension.Rows;
        # If null or less than 2 rows, there is no pre-existing data.
        If ($null -eq $Local:SheetRows -or $Local:SheetRows -lt 2) {
            Write-Host -ForegroundColor Cyan "No data found in worksheet $($WorkSheet.Name)";
            return @{};
        }

        [HashTable]$Local:EmailTable = @{};
        [Int]$Local:ColumnIndex = 2;
        foreach ($Local:Row in 2..$Local:SheetRows) {
            [String]$Local:Email = $WorkSheet.Cells[$Local:Row, $Local:ColumnIndex].Value;
            $Local:Email | Assert-NotNull -Message "Email was null";

            $Local:EmailTable.Add($Local:Email, $Local:Row);
        }

        return $Local:EmailTable;
    }
}

function Update-History([OfficeOpenXml.ExcelWorksheet]$ActiveWorkSheet, [OfficeOpenXml.ExcelWorksheet]$HistoryWorkSheet, [int]$KeepHistory = 4) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        # This is a new worksheet, no history to update
        if ($ActiveWorkSheet.Dimension.Columns -lt 4) {
            Write-Host -ForegroundColor Cyan "No data found in worksheet $($ActiveWorkSheet.Name), skipping history update."
            return
        }

        $TotalColumns = $ActiveWorkSheet.Dimension.Columns
        $RemovedColumns = 0
        $KeptRange = ($TotalColumns - $KeepHistory)..$TotalColumns
        foreach ($ColumnIndex in 4..$ActiveWorkSheet.Dimension.Columns) {
            $WillKeep = $KeptRange -contains $ColumnIndex
            $ColumnIndex = $ColumnIndex - $RemovedColumns
            $DateValue = $ActiveWorkSheet.Cells[1, $ColumnIndex].Value

            Write-Host -ForegroundColor Cyan "Processing Column $ColumnIndex which is dated $DateValue, moving to history: $(!$WillKeep)"

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
                        Write-Host -ForegroundColor Cyan "Deleting what is thought to be invalid or check column at $ColumnIndex"
                        # Probably the check column, remove and continue;
                        $ActiveWorkSheet.DeleteColumn($ColumnIndex)
                        $RemovedColumns++
                        continue
                    }
                }
            }

            Write-Host -ForegroundColor Cyan "Processing Column $ColumnIndex which is dated $Date, moving to history: $(!$WillKeep)"

            if ($WillKeep -eq $true) {
                continue
            }

            if ($null -ne $HistoryWorkSheet) {
                $HistoryColumnIndex = $HistoryWorkSheet.Dimension.Columns + 1

                Write-Host -ForegroundColor Cyan "Moving column $ColumnIndex from working page into history page at $HistoryColumnIndex"

                $HistoryWorkSheet.InsertColumn($HistoryColumnIndex, 1)
                $HistoryWorkSheet.Cells[1, $HistoryColumnIndex].Value = $Date.ToString('MMM-yy')

                $HistoryEmails = Get-EmailToCell -WorkSheet $HistoryWorkSheet
                foreach ($RowIndex in 2..$ActiveWorkSheet.Dimension.Rows) {
                    Write-Host -ForegroundColor Cyan "Processing row $RowIndex"

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
}

function Get-ColumnDate {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [OfficeOpenXml.ExcelWorksheet]$WorkSheet,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
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

function Invoke-CleanupWorksheet(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelWorksheet]$WorkSheet,

    [switch]$DuplicateCheck
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        $Rows = $WorkSheet.Dimension.Rows
        if ($null -ne $Rows -and $Rows -ge 2) {
            # Start from 2 because the first row is the header
            $RemovedRows = 0
            $VisitiedEmails = New-Object System.Collections.Generic.List[String]
            foreach ($RowIndex in 2..$WorkSheet.Dimension.Rows) {
                $RowIndex = $RowIndex - $RemovedRows
                $Email = $WorkSheet.Cells[$RowIndex, 2].Value

                Write-Host -ForegroundColor Cyan "Processing row $RowIndex with email '$Email'"

                # Remove any empty rows between actual data
                if ($null -eq $Email) {
                    Write-Host -ForegroundColor Cyan "Removing row $RowIndex because email is empty."
                    $WorkSheet.DeleteRow($RowIndex)
                    $RemovedRows++
                    continue
                }

                if ($DuplicateCheck) {
                    Write-Host -ForegroundColor Cyan "Checking for duplicate email '$Email'"

                    if (!$VisitiedEmails.Contains($Email)) {
                        Write-Host -ForegroundColor Cyan "Adding email '$Email' to the list of visited emails"
                        $VisitiedEmails.Add($Email)
                        continue
                    }

                    Write-Host -ForegroundColor Cyan "Duplicate email '$Email' found at virtual row $RowIndex (Offset by $($RemovedRows + 2))"

                    $AdditionalRealIndex = $RowIndex + $RemovedRows
                    $ExistingRealIndex = $VisitiedEmails.IndexOf($Email) + 2 + $RemovedRows
                    $Question = "Duplicate email found at row $AdditionalRealIndex`nThe email '$Email' was first seen at row $ExistingRealIndex.`nPlease select which row you would like to keep, or enter 'b' to break and manually review the file."
                    $Selection = Prompt-Selection "Duplicate Email" $Question @("&Existing", "&New", "&Break") 0
                    $RemovingRow = switch ($Selection) {
                        0 { $RowIndex }
                        1 {
                            $ExistingIndex = $VisitiedEmails.IndexOf($Email)
                            $VisitiedEmails.Remove($Email)
                            $VisitiedEmails.Add($Email)
                            $ExistingIndex
                        }
                        default {
                            Write-Error "Please manually review and remove the duplicate email that exists at rows $ExistingRealIndex and $AdditionalRealIndex"
                            Exit 1010
                        }
                    }

                    Write-Host -ForegroundColor Cyan "Removing row $RemovingRow "
                    $WorkSheet.DeleteRow($RemovingRow)
                    $RemovedRows++
                }
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
                    Write-Host -ForegroundColor Cyan "Removing column $ColumnIndex because date is empty or invalid."
                    $WorkSheet.DeleteColumn($ColumnIndex)
                    $RemovedColumns++
                    continue
                }
            }
        }
    }
}

<#
.SYNOPSIS
    Removes all users from the worksheet which aren't present within the new data.
#>
function Remove-Users([PSCustomObject[]]$NewData, [OfficeOpenXml.ExcelWorksheet]$WorkSheet) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        Trap {
            Write-Host -ForegroundColor Red "Unexpected error occurred while removing users from worksheet";
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        };

        [HashTable]$Local:EmailTable = Get-EmailToCell -WorkSheet $WorkSheet;
        $Local:EmailTable | Assert-NotNull -Message 'Email table was null';

        # Sort decenting by value, so that we can remove from the bottom up without affecting the index.
        [HashTable]$Local:EmailTable = $Local:EmailTable | Sort-Object -Property Values -Descending;

        $Local:EmailTable | ForEach-Object {
            [String]$Local:ExistingEmail = $_.Name;
            [Int]$Local:ExistingRow = $_.Value;

            # Find the object in the new data which matches the existing email.
            [String]$Local:NewData = $NewData | Where-Object { $_.Email -eq $Local:ExistingEmail } | Select-Object -First 1;
            If ($null -eq $Local:NewData) {
                Write-Host -ForegroundColor Cyan -Object "$Local:ExistingEmail is not longer present in the new data, removing from row $Local:ExistingRow";
                $WorkSheet.DeleteRow($Local:ExistingRow);
            }
        }
    }
}

<#
.SYNOPSIS
    Adds all users from the new data which aren't present within the worksheet.
#>
function Add-Users([PSCustomObject[]]$NewData, [OfficeOpenXml.ExcelWorksheet]$WorkSheet) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        Trap {
            Write-Host -ForegroundColor Red "Unexpected error occurred while adding users to worksheet";
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        };

        [HashTable]$Local:EmailTable = Get-EmailToCell -WorkSheet $WorkSheet;
        $Local:EmailTable | Assert-NotNull -Message 'Email table was null';

        [PSCustomObject]$Local:NewUsers = $NewData | Where-Object { -not $Local:EmailTable.ContainsKey($_.Email) };
        If ($null -eq $Local:NewUsers) {
            Write-Host -ForegroundColor Cyan -Object "No new users found, skipping add users.";
            return;
        }

        # Create a new Email table, but this time with the insertions of users
        # Each value is a boolean which is only true if they are a new user.
        # This should be sorted by displayName, so that we can insert them in the correct order.
        [HashTable]$Local:TableWithInsertions = @{};
        $Local:EmailTable.GetEnumerator().ForEach({$Local:TableWithInsertions.Add($_.Key, $false); });
        $Local:NewUsers | ForEach-Object { $Local:TableWithInsertions.Add($_.Email, $true); };
        [Object[]]$Local:TableWithInsertions = $Local:TableWithInsertions.GetEnumerator() | Sort-Object -Property Key;

        [Int]$Local:LastRow = 1;
        $Local:TableWithInsertions | ForEach-Object {
            $Local:LastRow++;
            [String]$Local:Email = $_.Key;
            [Boolean]$Local:IsNewUser = $_.Value;

            If ($Local:IsNewUser) {
                Write-Host -ForegroundColor Cyan -Object "$Local:Email is a new user, inserting into row $($Local:LastRow + 1)";

                [PSCustomObject]$Local:NewUserData = $NewData | Where-Object { $_.Email -eq $Local:Email } | Select-Object -First 1;
                # $Local:NewUserData | Assert-NotNull -Message 'New user data was null';

                $WorkSheet.InsertRow($Local:LastRow, 1);
                $WorkSheet.Cells[$Local:LastRow, 1].Value = $Local:NewUserData.DisplayName;
                $WorkSheet.Cells[$Local:LastRow, 2].Value = $Local:NewUserData.Email;
                $WorkSheet.Cells[$Local:LastRow, 3].Value = $Local:NewUserData.MobilePhone;
            }
        }
    }
}

function Invoke-OrderUsers(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelWorksheet]$WorkSheet
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        Trap {
            Write-Host -ForegroundColor Red "Unexpected error occurred while re-ordering users";
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        };

        return

        [HashTable]$Local:EmailTable = Get-EmailToCell -WorkSheet $WorkSheet;
        [HashTable]$Local:RequiresSorting = @{};
        foreach ($Local:Index in $Local:EmailTable.Values) {
            [String]$Local:DisplayName = $WorkSheet.Cells[$Local:Index, 1].Value;
            $Local:RequiresSorting.Add($Local:DisplayName, $Local:Index);
        }
        $Local:RequiresSorting | Assert-NotNull -Message 'Requires sorting was null';

        [Int]$Local:SortedRows = 0;
        while ($Local:RequiresSorting.Count -gt 0) {
            [String]$Local:SmallestKey = $Local:RequiresSorting.Keys[0];

            foreach ($Local:Key in $Local:RequiresSorting.Keys) {
                If ($Local:Key -lt $Local:SmallestKey) {
                    $Local:SmallestKey = $Local:Key;
                }
            }

            Write-Host -ForegroundColor Cyan -Object "Smallest key is $Local:SmallestKey";

            [Int]$Local:CurrentIndex = $Local:RequiresSorting[$Local:SmallestKey];
            [Int]$Local:ShouldBeAt = $Local:SortedRows++ + 2;

            If ($Local:CurrentIndex -ne $Local:ShouldBeAt) {
                Write-Host -ForegroundColor Cyan -Object "Moving row $Local:CurrentIndex to row $Local:ShouldBeAt";

                $WorkSheet.InsertRow($Local:ShouldBeAt, 1);
                foreach ($Local:Column in (1..$WorkSheet.Dimension.Columns)) {
                    $Local:Value = $WorkSheet.Cells[$Local:CurrentIndex, $Local:Column].Text;
                    $WorkSheet.Cells[$Local:ShouldBeAt, $Local:Column].Value = $Local:Value;
                }

                $WorkSheet.DeleteRow($Local:CurrentIndex);

                foreach ($Local:Key in $Local:RequiresSorting.Clone().Keys) {
                    [Int]$Local:Value = $Local:RequiresSorting[$Local:Key];

                    If ($Local:Value -lt $Local:CurrentIndex) {
                        $Local:RequiresSorting[$Local:Key] = $Local:Value + 1;
                    }
                }
            }

            $Local:RequiresSorting.Remove($Local:SmallestKey);
        }
    }
}

<#
.SYNOPSIS
    Updates the worksheet with the new data.
.DESCRIPTION
    This function will update the worksheet,
    Adding new users in their correct row ordered by their display name,
    and insert a new column for the current month with the correct header.
#>
function Update-Data([PSCustomObject[]]$NewData, [OfficeOpenXml.ExcelWorksheet]$WorkSheet, [switch]$AddNewData) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        Trap {
            Write-Host -ForegroundColor Red "Unexpected error occurred while updating data";
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        };

        # We have already re-ordered, and inserted new users, so now we just need to add a new column for the current month.
        [HashTable]$Local:EmailTable = Get-EmailToCell -WorkSheet $WorkSheet;
        $Local:EmailTable | Assert-NotNull -Message 'Email table was null';

        # Only insert new column if required.
        If ($AddNewData) {
            [String]$Local:NewColumnName = Get-Date -Format "MMM-yy";
            [Int]$Local:NewColumnIndex = [Math]::Max(3, $WorkSheet.Dimension.Columns + 1);
            $WorkSheet.Cells[1, $Local:NewColumnIndex].Value = $Local:NewColumnName;
        }

        foreach ($Local:User in $NewData) {
            [String]$Local:Email = $Local:User.Email;
            [Int]$Local:Row = $Local:EmailTable[$Local:Email];

            if ($null -eq $Local:Row -or $Local:Row -eq 0) {
                Write-Host -ForegroundColor Cyan -Object "$Local:Email doesn't exist in this sheet yet, skipping.";
                continue;
            }

            Write-Host -ForegroundColor Cyan -Object "Updating row $Local:Row with new data";

            $WorkSheet.Cells[$Local:Row, 1].Value = $Local:User.DisplayName;
            $WorkSheet.Cells[$Local:Row, 2].Value = $Local:User.Email;
            $WorkSheet.Cells[$Local:Row, 3].Value = $Local:User.MobilePhone;

            If ($AddNewData) {
                $Local:Cell = $WorkSheet.Cells[$Local:Row, $Local:NewColumnIndex];
                $Local:Cell.Value = $Local:User.MFA_Phone;
                $Local:Cell.Style.Numberformat.Format = "@";
                $Local:Cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::None;
            }
        }
    }
}

function Set-Check(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelWorksheet]$WorkSheet
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

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

            Write-Host -ForegroundColor Cyan "Setting cell $row,$checkColumn to $colour"

            $Cell.Value = $Result
            $Cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            $Cell.Style.Fill.BackgroundColor.SetColor(($Colour))
        }

        $Cells[1, $checkColumn].Value = 'Check'
    }
}

function Set-Styles(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelWorksheet]$WorkSheet
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        $lastColumn = $WorkSheet.Dimension.Address -split ':' | Select-Object -Last 1
        $lastColumn = $lastColumn -replace '[0-9]', ''

        Set-ExcelRange -Worksheet $WorkSheet -Range "A1:$($lastColumn)1" -Bold -HorizontalAlignment Center
        if ($WorkSheet.Dimension.Columns -ge 4) { Set-ExcelRange -Worksheet $WorkSheet -Range "D1:$($lastColumn)1" -NumberFormat "MMM-yy" }
        Set-ExcelRange -Worksheet $WorkSheet -Range "A2:$($lastColumn)$(($WorkSheet.Dimension.Rows))" -AutoSize -ResetFont -BackgroundPattern Solid
        # Set-ExcelRange -Worksheet $WorkSheet -Range "A2:$($lastColumn)$($WorkSheet.Dimension.Rows)"  # [System.Drawing.Color]::LightSlateGray
        # Set-ExcelRange -Worksheet $WorkSheet -Range "D2:$($lastColumn)$($WorkSheet.Dimension.Rows)" -NumberFormat "[<=9999999999]####-###-###;+(##) ###-###-###"
    }
}

function New-BaseWorkSheet([Parameter(Mandatory)][ValidateNotNullOrEmpty()][OfficeOpenXml.ExcelWorksheet]$WorkSheet) {
    # Test if the worksheet has data by checking the dimension
    # If the dimension is null then there is no data
    if ($null -ne $WorkSheet.Dimension) {
        return
    }

    $WorkSheet.InsertColumn(1, 3)
    $WorkSheet.InsertRow(1, 1)

    $Local:Cells = $WorkSheet.Cells
    $Local:Cells[1, 1].Value = "Name"
    $Local:Cells[1, 2].Value = "Email"
    $Local:Cells[1, 3].Value = "Phone"
}

function Get-ActiveWorkSheet(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelPackage]$ExcelData
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:ActiveWorkSheet; }

    process {
        [OfficeOpenXml.ExcelWorksheet]$Local:ActiveWorkSheet = $ExcelData.Workbook.Worksheets | Where-Object { $_.Name -eq 'Working' };
        if ($null -eq $Local:ActiveWorkSheet) {
            [OfficeOpenXml.ExcelWorksheet]$Local:ActiveWorkSheet = $ExcelData.Workbook.Worksheets.Add('Working')
        } else { $Local:ActiveWorkSheet.Name = "Working" }

        # Move the worksheets to the correct position
        $ExcelData.Workbook.Worksheets.MoveToStart("Working")

        New-BaseWorkSheet -WorkSheet $Local:ActiveWorkSheet;

        return $Local:ActiveWorkSheet;
    }
}

function Get-HistoryWorkSheet(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelPackage]$ExcelData
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:HistoryWorkSheet; }

    process {
        [OfficeOpenXml.ExcelWorksheet]$Local:HistoryWorkSheet = $ExcelData.Workbook.Worksheets[2]
        if ($null -eq $HistoryWorkSheet -or $HistoryWorkSheet.Name -ne "History") {
            Write-Host -ForegroundColor Cyan "Creating new worksheet for history"
            $HistoryWorkSheet = $ExcelData.Workbook.Worksheets.Add("History")
        }

        # Move the worksheets to the correct position
        $ExcelData.Workbook.Worksheets.MoveAfter("History", "Working")

        New-BaseWorkSheet -WorkSheet $Local:HistoryWorkSheet;

        return $Local:HistoryWorkSheet;
    }
}

function Save-Excel([OfficeOpenXml.ExcelPackage]$ExcelData) {
    begin { Enter-Scope $MyInvocation }

    process {
        if ($ExcelData.Workbook.Worksheets.Count -gt 2) {
            Write-Host -ForegroundColor Cyan "Removing $($ExcelData.Workbook.Worksheets.Count - 2) worksheets"
            foreach ($Index in 3..$ExcelData.Workbook.Worksheets.Count) {
                $ExcelData.Workbook.Worksheets.Delete(3)
            }
        }

        Close-ExcelPackage $ExcelData -Show #-SaveAs "$ExcelFile.new.xlsx"
    }

    end { Exit-Scope $MyInvocation }
}

function Main {
    begin { Enter-Scope -Invocation $MyInvocation; }

    process {
        Trap {
            Write-Host -ForegroundColor Red "Unexpected error occurred while running main";
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        };

        Invoke-SetupEnvironment;

        [PSCustomObject[]]$Local:NewData = Get-CurrentData;
        [OfficeOpenXml.ExcelPackage]$Local:ExcelData = Get-Excel;

        [OfficeOpenXml.ExcelWorksheet]$Local:ActiveWorkSheet = Get-ActiveWorkSheet -ExcelData $Local:ExcelData;
        [OfficeOpenXml.ExcelWorksheet]$Local:HistoryWorkSheet = Get-HistoryWorkSheet -ExcelData $Local:ExcelData;
        $Local:ActiveWorkSheet | Assert-NotNull -Message 'ActiveWorkSheet was null';
        $Local:HistoryWorkSheet | Assert-NotNull -Message 'HistoryWorkSheet was null';

        Invoke-CleanupWorksheet -WorkSheet $Local:ActiveWorkSheet -DuplicateCheck;
        Invoke-CleanupWorksheet -WorkSheet $Local:HistoryWorkSheet;

        Update-History -HistoryWorkSheet $Local:HistoryWorkSheet -ActiveWorkSheet $Local:ActiveWorkSheet;

        Remove-Users -NewData $Local:NewData -WorkSheet $Local:ActiveWorkSheet;
        Add-Users -NewData $Local:NewData -WorkSheet $Local:ActiveWorkSheet;

        Update-Data -NewData $Local:NewData -WorkSheet $Local:ActiveWorkSheet -AddNewData;
        Update-Data -NewData $Local:NewData -WorkSheet $Local:HistoryWorkSheet;

        Invoke-OrderUsers -WorkSheet $Local:ActiveWorkSheet;
        Invoke-OrderUsers -WorkSheet $Local:HistoryWorkSheet;

        Set-Check -WorkSheet $Local:ActiveWorkSheet

        @($Local:ActiveWorkSheet, $Local:HistoryWorkSheet) | ForEach-Object { Set-Styles -WorkSheet $_ }

        Save-Excel -ExcelData $Local:ExcelData
    }

    end { Exit-Scope $MyInvocation }
}

Main
