#Requires -Version 7

Using module ..\..\common\Environment.psm1
Using module ..\..\common\Connection.psm1
Using module ..\..\common\Logging.psm1
Using module ..\..\common\Ensure.psm1
Using module ..\..\common\Scope.psm1
Using module ..\..\common\Exit.psm1
Using module ..\..\common\Assert.psm1
Using module ..\..\common\Input.psm1

Using module PSToml
Using module ImportExcel
Using module Microsoft.Graph.Users
Using module Microsoft.Graph.Authentication
Using module Microsoft.Graph.Identity.SignIns

[CmdletBinding(SupportsShouldProcess)]
Param(
    [Parameter(Mandatory)]
    [String]$Client,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$ClientsFolder,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]$ExcelFileName = 'MFA Numbers.xlsx'
)

$Script:Columns = @{
    DisplayName = 1;
    Email       = 2;
    Phone       = 3;
};

# Section Start - Main Functions

function Invoke-SetupEnvironment(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Client,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$ClientsFolder,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$ExcelFileName
) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        Invoke-EnsureUser;
        Connect-Service -Services 'Graph' -Scopes 'User.Read.All','UserAuthenticationMethod.Read.All';

        # Get the first client folder that exists
        $Local:ReportFolder = "$ClientFolder/Monthly Report"
        $Script:ExcelFile = "$Local:ReportFolder/$ExcelFileName"

        if ((Test-Path $Local:ReportFolder) -eq $false) {
            Invoke-Info "Report folder not found; creating $Local:ReportFolder";
            New-Item -Path $Local:ReportFolder -ItemType Directory | Out-Null;
        }

        if (Test-Path $Script:ExcelFile) {
            Invoke-Info "Excel file found; creating backup $Script:ExcelFile.bak";
            Copy-Item -Path $Script:ExcelFile -Destination "$Script:ExcelFile.bak" -Force;
        }
    }
}

<#
.SYNOPSIS
Get the up to date online data from MSOL for user auth methods.

.NOTES
The returned data is a PSCustomObject with the following properties:
    Email
    DisplayName
    Password
        Enabled
        Change
    MFA
        Phone
        Email
        App
        Fido

It is ordered by DisplayName.
#>
function Get-CurrentData {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:ExpandedUsers; }

    process {
        $LicensedUsers = Get-MgUser -Filter '(assignedLicenses/$count ne 0) and (AccountEnabled eq true)' -ConsistencyLevel eventual -CountVariable LicensedUserCount -All;

        # The following common parameters are not currently supported in the Parallel parameter set: ErrorAction, WarningAction, InformationAction, PipelineVariable
        $Global:PSDefaultParameterValues['Disabled'] = $True;
        $ExpandedUsers = $LicensedUsers | ForEach-Object -Parallel {
            $User = $_;
            $AuthMethods = Get-MgUserAuthenticationMethod -UserId $User.Id | ForEach-Object {
                $Properties = $_ | Select-Object -ExpandProperty AdditionalProperties
                $Properties.Add('Id', $_.Id)

                $Properties
            }

            $PasswordAuth = $AuthMethods | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.passwordAuthenticationMethod' }
            $PhoneAuth = $AuthMethods | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.phoneAuthenticationMethod' }
            $EmailAuth = $AuthMethods | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.emailAuthenticationMethod' }
            $AppAuth = $AuthMethods | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod' }

            # We want to skip the Android and iOS devices, as they are not FIDO2 keys but rather the app registering as a FIDO2 key.
            $FidoAuth = $AuthMethods | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.fido2AuthenticationMethod' } `
            | Where-Object { $_.model.StartsWith('Microsoft Authenticator') -eq $False };

            # Looks like these now get registered with the DisplayName being the Computer's Name
            # However old ones don't have these details so we are just going to ignore them for now.
            $WindowsHelloAuth = $AuthMethods | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod' } `
            | Where-Object { [String]::IsNullOrEmpty($_.displayName) -eq $false };

            $UserData = @{
                DisplayName     = $User.DisplayName;
                Email           = $null;

                # TODO - Can i find the IP / location of the last password change?
                PasswordChanged = [DateTime]::ParseExact($PasswordAuth.createdDateTime, 'yyyy-MM-dd\TH:mm:ss\Z', $null);

                MFA             = @{ }
            };

            function Format-SingleOrList([Object]$Value, [ScriptBlock]$Format) {
                if ($null -eq $Value) {
                    return $null;
                }

                if ($Value.GetType() -eq [Object[]]) {
                    return $Value | ForEach-Object { Format-SingleOrList $_ $Format }
                }

                return & $Format $Value;
            }

            if ($null -ne $User.UserPrincipalName) {
                $UserData.Email = $User.UserPrincipalName
            } else {
                $UserData.Email = $User.Mail;
            }

            # TODO - Validate each MFA method is enabled against entra policies
            # -and $PhoneAuth.smsSignInState -ne 'notAllowedByPolicy'
            if ($null -ne $PhoneAuth) {
                $UserData.MFA.Phone = $PhoneAuth.phoneNumber;
            }
            if ($null -ne $EmailAuth -and $EmailAuth.emailSignInState -ne 'notAllowedByPolicy') {
                $UserData.MFA.Email = $EmailAuth.emailAddress;
            }
            # TODO - Can i find the IP / location that registered the App?
            if ($null -ne $AppAuth -and $AppAuth.appSignInState -ne 'notAllowedByPolicy') {
                $UserData.MFA.App = Format-SingleOrList $AppAuth { "$($args[0].deviceTag) $($args[0].displayName) - $($args[0].Id)" };
            }
            if ($null -ne $FidoAuth) {
                # Display Name should contain a unique identifier like a S\N
                $UserData.MFA.Fido = Format-SingleOrList $FidoAuth { "$($args[0].model) - $($args[0].displayName)" };
            }
            if ($null -ne $WindowsHelloAuth) {
                $UserData.MFA.WindowsHello = $WindowsHelloAuth.displayName;
            }

            return $UserData;
        }

        $Global:PSDefaultParameterValues.Remove('Disabled');
        return $ExpandedUsers;
    }
}

function Get-Excel {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $Local:Import = if (Test-Path $Script:ExcelFile) {
            Invoke-Info 'Excel file found, importing data...';
            try {
                Import-Excel $Script:ExcelFile
            } catch {
                Invoke-Error 'Failed to import Excel file.';

                $Local:Message = $_.Exception.Message
                $Local:WriteMessage = switch -Regex ($Local:Message) {
                    'Duplicate column headers' {
                        [System.Text.RegularExpressions.Match]$Local:Match = Select-String "Duplicate column headers found on row '(?<row>[0-9]+)' in columns '(?:(?<column>[0-9]+)(?:[ ]?))+'." -InputObject $_
                        [String]$Row = $Match.Matches.Groups[1].Captures;
                        [String]$Columns = $Match.Matches.Groups[2].Captures;

                        "There were duplicate columns found on row $Row in columns $($Columns -join ', '); Please remove any duplicate columns and try again";
                    }
                    default { 'Unknown error; Please examine the error message and try again'; }
                }

                Invoke-Error $WriteMessage;
                exit 1004;
            }
        } else {
            Invoke-Info 'Excel file not found, creating new file...';
            New-Object -TypeName System.Collections.ArrayList;
        }

        $Local:Import | Export-Excel "$Script:ExcelFile" -PassThru -AutoSize -FreezeTopRowFirstColumn;
    }
}

function Get-EmailToCell([Parameter(Mandatory)][ValidateNotNullOrEmpty()][OfficeOpenXml.ExcelWorksheet]$WorkSheet) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:EmailTable; }

    process {
        [Int]$Local:SheetRows = $WorkSheet.Dimension.Rows;
        # If null or less than 2 rows, there is no pre-existing data.
        If ($null -eq $Local:SheetRows -or $Local:SheetRows -lt 2) {
            Invoke-Info "No data found in worksheet $($WorkSheet.Name)";
            return @{};
        }

        [HashTable]$Local:EmailTable = @{};
        [Int]$Local:ColumnIndex = 2;
        foreach ($Local:Row in 2..$Local:SheetRows) {
            [String]$Local:Email = $WorkSheet.Cells[$Local:Row, $Local:ColumnIndex].Value;
            $Local:Email | Assert-NotNull -Message 'Email was null';

            $Local:EmailTable.Add($Local:Email, $Local:Row);
        }

        return $Local:EmailTable;
    }
}

function Update-History([OfficeOpenXml.ExcelWorksheet]$ActiveWorkSheet, [OfficeOpenXml.ExcelWorksheet]$HistoryWorkSheet, [int]$KeepHistory = 4) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        # This is a new worksheet, no history to update
        if ($ActiveWorkSheet.Dimension.Columns -lt 4) {
            Invoke-Info "No data found in worksheet $($ActiveWorkSheet.Name), skipping history update."
            return
        }

        [Int]$Local:TotalColumns = $ActiveWorkSheet.Dimension.Columns;
        [Int]$Local:RemovedColumns = 0;
        $Local:KeptRange = ($TotalColumns - $KeepHistory)..$TotalColumns;
        foreach ($Local:ColumnIndex in 4..$ActiveWorkSheet.Dimension.Columns) {
            [Boolean]$Local:WillKeep = $Local:KeptRange -contains $Local:ColumnIndex;
            [Int]$ColumnIndex = $Local:ColumnIndex - $Local:RemovedColumns;
            [String]$Local:DateValue = $ActiveWorkSheet.Cells[1, $Local:ColumnIndex].Value;

            Invoke-Info "Processing Column $Local:ColumnIndex which is dated $Local:DateValue, moving to history: $(-not $Local:WillKeep)"

            # Empty column, remove and continue;
            if ($null -eq $Local:DateValue -or $Local:DateValue -eq '') {
                $ActiveWorkSheet.DeleteColumn($Local:ColumnIndex);
                $Local:RemovedColumns++;
                continue;
            }

            # This is absolutely fucking revolting
            [DateTime]$Local:Date = try {
                Get-Date -Date ($Local:DateValue);
            } catch {
                try {
                    Get-Date -Date "$($Local:DateValue)-$(Get-Date -Format 'yyyy')";
                } catch {
                    try {
                        [DateTime]::FromOADate($Local:DateValue);
                    } catch {
                        Invoke-Info "Deleting what is thought to be invalid or check column at $Local:ColumnIndex";
                        # Probably the check column, remove and continue;
                        $ActiveWorkSheet.DeleteColumn($Local:ColumnIndex);
                        $Local:RemovedColumns++;
                        continue;
                    }
                }
            }

            if ($Local:WillKeep) {
                continue;
            }

            if ($null -ne $HistoryWorkSheet) {
                [Int]$Local:HistoryColumnIndex = $HistoryWorkSheet.Dimension.Columns + 1;

                Invoke-Info "Moving column $Local:ColumnIndex from working page into history page at $Local:HistoryColumnIndex";

                $HistoryWorkSheet.InsertColumn($Local:HistoryColumnIndex, 1);
                $HistoryWorkSheet.Cells[1, $Local:HistoryColumnIndex].Value = $Local:Date.ToString('MMM-yy');

                [HashTable]$Local:HistoryEmails = Get-EmailToCell -WorkSheet $HistoryWorkSheet;
                foreach ($Local:RowIndex in 2..$ActiveWorkSheet.Dimension.Rows) {
                    Invoke-Info "Processing row $Local:RowIndex";

                    [String]$Local:Email = $ActiveWorkSheet.Cells[$RowIndex, 2].Value;
                    [Int]$Local:HistoryIndex = $HistoryEmails[$Email];

                    if ($null -eq $Local:HistoryIndex -or $HistoryIndex -eq 0) {
                        [Int]$Local:HistoryIndex = $HistoryWorkSheet.Dimension.Rows + 1;
                        $HistoryWorkSheet.InsertRow($Local:HistoryIndex, 1);
                        $HistoryWorkSheet.Cells[$Local:HistoryIndex, 2].Value = $Local:Email;
                    } else {
                        # Update the name and phone number
                        $Local:HistoryWorkSheet.Cells[$Local:HistoryIndex, 1].Value = $ActiveWorkSheet.Cells[$Local:RowIndex, 1].Value;
                        $Local:HistoryWorkSheet.Cells[$Local:HistoryIndex, 3].Value = $ActiveWorkSheet.Cells[$Local:RowIndex, 3].Value;
                    }

                    $HistoryWorkSheet.Cells[$Local:HistoryIndex, $Local:HistoryColumnIndex].Value = $ActiveWorkSheet.Cells[$Local:RowIndex, $Local:ColumnIndex].Value;
                }
            }

            $ActiveWorkSheet.DeleteColumn($Local:ColumnIndex);
            $Local:RemovedColumns++;
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

    $Local:DateValue = $WorkSheet.Cells[1, $ColumnIndex].Value
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
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [Int]$Local:Rows = $WorkSheet.Dimension.Rows;
        if ($null -ne $Local:Rows -and $Local:Rows -ge 2) {
            # Start from 2 because the first row is the header
            [Int]$Local:RemovedRows = 0;
            [System.Collections.Generic.List[String]]$Local:VisitiedEmails = New-Object System.Collections.Generic.List[String];

            foreach ($Local:RowIndex in 2..$Local:Rows) {
                [Int]$Local:RowIndex = $Local:RowIndex - $Local:RemovedRows;
                [String]$Local:Email = $WorkSheet.Cells[$Local:RowIndex, $Script:Columns.Email].Value;

                # Remove any empty rows between actual data
                if ($null -eq $Local:Email) {
                    Invoke-Info "Removing row $Local:RowIndex because email is empty.";
                    $WorkSheet.DeleteRow($RowIndex);
                    $Local:RemovedRows++;
                    continue;
                }

                if ($DuplicateCheck) {
                    Invoke-Info "Checking for duplicate email '$Local:Email'";

                    if (!$Local:VisitiedEmails.Contains($Local:Email)) {
                        Invoke-Info "Adding email '$Local:Email' to the list of visited emails";
                        $Local:VisitiedEmails.Add($Local:Email);
                        continue;
                    }

                    Invoke-Info "Duplicate email '$Local:Email' found at virtual row $Local:RowIndex (Offset by $($Local:RemovedRows + 2))";

                    [Int]$Local:AdditionalRealIndex = $Local:RowIndex + $Local:RemovedRows;
                    [Int]$Local:ExistingRealIndex = $Local:VisitiedEmails.IndexOf($Local:Email) + 2 + $Local:RemovedRows;

                    # TODO :: FIXME
                    if ($False) {
                        function Get-RowColumns([Int]$RowIndex) {
                            $Local:ColumnRange = 1..$WorkSheet.Dimension.Columns;
                            [String[]]$Local:Row = $Local:ColumnRange | ForEach-Object { $WorkSheet.Cells[$RowIndex, $_].Text };

                            $Local:Row;
                        }

                        function Invoke-FormattedRows([Int[]]$RowIndexes) {
                            [String[]]$Local:Rows = $RowIndexes | ForEach-Object { Get-RowColumns $_ };

                            Invoke-Info "Formatting rows: $($Local:Rows -join ', ')";

                            [HashTable]$Local:LongestColumns = @{};
                            $Rows | ForEach-Object {
                                [String[]]$Local:Row = $_;
                                [Int]$Local:Index = -1;

                                $Local:Row | ForEach-Object {
                                    [Int]$Local:Index++;
                                    [String]$Local:Value = $_;
                                    [Int]$Local:ValueLength = $Local:Value.Length;

                                    [Int]$Local:CurrentLongest = $Local:LongestColumns[$Local:Index];
                                    If ($null -eq $Local:CurrentLongest -or $Local:CurrentLongest -lt $Local:ValueLength) {
                                        $Local:LongestColumns[$Local:Index] = $Local:ValueLength;
                                    }
                                }
                            }

                            Invoke-Info "Longest columns: $($Local:LongestColumns.Values | ForEach-Object { $_ })";

                            [Int]$Local:TerminalWidth = $Host.UI.RawUI.BufferSize.Width;
                            [Int]$Local:MustIncludeLength = $Local:LongestColumns[0] + $Local:LongestColumns[1] + $Local:LongestColumns[2];
                            [Int]$Local:MaxColumnLength = $Local:TerminalWidth - $Local:MustIncludeLength;

                            Invoke-Info "Terminal width: $Local:TerminalWidth";
                            Invoke-Info "Must include length: $Local:MustIncludeLength";
                            Invoke-Info "Max column length: $Local:MaxColumnLength";

                            # Starting collecting the columns from the end of the array, if the combined length of the columns is greater than our max length, stop collecting.
                            [Int]$Local:CollectingColumns = $Local:LongestColumns.Count - 1;
                            [Int]$Local:CurrentLength = 0;
                            while ($Local:CollectingColumns -ge 0) {
                                [Int]$Local:CurrentLength += $Local:LongestColumns[$Local:CollectingColumns];
                                If ($Local:CurrentLength -gt $Local:MaxColumnLength) {
                                    break;
                                }

                                $Local:CollectingColumns--;
                            }

                            # With the columns we want to display, we can now format the rows.
                            [String[]]$Local:Lines = '';
                            $Rows | ForEach-Object {
                                [String[]]$Local:Row = $_;
                                for ($Local:Index = $Local:CurrentLongest - 1; $Local:Index -le ($Local:LongestColumns.Count - 1); $Local:Index++) {
                                    [String]$Local:Value = $Local:Row[$Local:Index];
                                    [Int]$Local:ValueLength = $Local:Value.Length;

                                    [Int]$Local:Padding = $Local:LongestColumns[$Local:Index] - $Local:ValueLength;
                                    [String]$Local:PaddingString = ' ' * $Local:Padding;

                                    "$Local:Value$Local:PaddingString";
                                }

                                $Local:Lines += ($Local:Columns -join ' | ');
                            }

                            $Local:Lines -join "`n";
                        }

                        # $(Invoke-FormattedRows 1,$Local:VisitiedEmails.IndexOf($Local:Email),$Local:RowIndex);
                    }

                    [String]$Local:Selection = Get-UserSelection `
                        -Title "Duplicate email found at row $Local:AdditionalRealIndex." `
                        -Question @"
The email '$Local:Email' was first seen at row $Local:ExistingRealIndex.
Please select which row you would like to keep, or enter 'b' to exit and manually review the file.
"@ `
                        -Choices @('Existing', 'New', 'Break') `
                        -DefaultChoice 0;

                    $Local:RemovingRow = switch ($Local:Selection) {
                        'Existing' { $RowIndex }
                        'New' {
                            $Local:ExistingIndex = $Local:VisitiedEmails.IndexOf($Local:Email);
                            $Local:VisitiedEmails.Remove($Local:Email);
                            $Local:VisitiedEmails.Add($Local:Email);
                            $Local:ExistingIndex;
                        }
                        default {
                            Invoke-Error "Please manually review and remove the duplicate email that exists at rows $Local:ExistingRealIndex and $Local:AdditionalRealIndex"
                            Exit 1010
                        }
                    }

                    Invoke-Verbose "Removing row $Local:RemovingRow";
                    $WorkSheet.DeleteRow($RemovingRow);
                    $Local:RemovedRows++;
                }
            }
        }

        [Int]$Local:Columns = $WorkSheet.Dimension.Columns;
        # Start from 4 because the first three columns are name,email,phone
        if ($null -ne $Local:Columns -and $Local:Columns -ge 4) {
            $Local:RemovedColumns = 0;
            foreach ($Local:ColumnIndex in 4..$WorkSheet.Dimension.Columns) {
                $Local:ColumnIndex = $Local:ColumnIndex - $Local:RemovedColumns;

                # Remove any empty columns, or invalid date columns between actual data
                # TODO -> Use Get-ColumnDate
                [String]$Local:Value = $WorkSheet.Cells[1, $Local:ColumnIndex].Value;
                if ($null -eq $Local:Value -or $Local:Value -eq 'Check') {
                    Invoke-Verbose "Removing column $Local:ColumnIndex because date is empty or invalid.";
                    $WorkSheet.DeleteColumn($Local:ColumnIndex);
                    $Local:RemovedColumns++;
                    continue;
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
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [HashTable]$EmailTable = Get-EmailToCell -WorkSheet $WorkSheet;
        $EmailTable | Assert-NotNull -Message 'Email table was null';

        # Sort decenting by value, so that we can remove from the bottom up without affecting the index during the operation.
        [HashTable]$EmailTable = $EmailTable | Sort-Object -Property Values -Descending;

        $EmailTable.Values | Sort-Object -Descending | ForEach-Object {
            [Int]$ExistingRow = $_;
            [String]$ExistingEmail = $EmailTable.GetEnumerator() | Where-Object { $_.Value -eq $ExistingRow } | Select-Object -First 1 -ExpandProperty Name;

            Invoke-Verbose "Checking if $Local:ExistingEmail exists in the new data";
            [PSCustomObject]$Local:NewDataInstance = $NewData | Where-Object { $_.Email -eq $Local:ExistingEmail } | Select-Object -First 1;
            Invoke-Debug "New data instance for $Local:ExistingEmail is $($Local:NewDataInstance | ConvertTo-Json)";
            If ($null -eq $Local:NewDataInstance) {
                Invoke-Verbose "$Local:ExistingEmail is no longer present in the new data, removing from row $Local:ExistingRow";
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
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [HashTable]$Local:EmailTable = Get-EmailToCell -WorkSheet $WorkSheet;
        $Local:EmailTable | Assert-NotNull -Message 'Email table was null';

        [PSCustomObject[]]$Local:NewUsers = $NewData | Where-Object { try {
                -not $Local:EmailTable.ContainsKey($_.Email)
            } catch {
                Write-Error "Failed to check if email exists in table: $_";
            } };
        If ($null -eq $Local:NewUsers) {
            Invoke-Debug 'No new users found, skipping add users.';
            return;
        }

        # Create a new Email table, but this time with the insertions of users
        # Each value is a boolean which is only true if they are a new user.
        # This should be sorted by displayName, so that we can insert them in the correct order.
        [HashTable]$Local:TableWithInsertions = @{};
        $Local:EmailTable.GetEnumerator().ForEach({ $Local:TableWithInsertions.Add($_.Key, $false); });
        $Local:NewUsers | ForEach-Object { $Local:TableWithInsertions.Add($_.Email, $true); };
        [Object[]]$Local:TableWithInsertions = $Local:TableWithInsertions.GetEnumerator() | Sort-Object -Property Key;

        [Int]$Local:LastRow = 1;
        $Local:TableWithInsertions | ForEach-Object {
            $Local:LastRow++;
            [String]$Local:Email = $_.Key;
            [Boolean]$Local:IsNewUser = $_.Value;

            If ($Local:IsNewUser) {
                Invoke-Verbose "$Local:Email is a new user, inserting into row $($Local:LastRow + 1)";

                [PSCustomObject]$Local:NewUserData = $NewData | Where-Object { $_.Email -eq $Local:Email } | Select-Object -First 1;

                $WorkSheet.InsertRow($Local:LastRow, 1);
                $WorkSheet.Cells[$Local:LastRow, 1].Value = $Local:NewUserData.DisplayName;
                $WorkSheet.Cells[$Local:LastRow, 2].Value = $Local:NewUserData.Email;
                $WorkSheet.Cells[$Local:LastRow, 3].Value = $null;
            }
        }
    }
}

function Invoke-OrderUsers(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelWorksheet]$WorkSheet
) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
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

            Invoke-Debug "Smallest key is $Local:SmallestKey";

            [Int]$Local:CurrentIndex = $Local:RequiresSorting[$Local:SmallestKey];
            [Int]$Local:ShouldBeAt = $Local:SortedRows++ + 2;

            If ($Local:CurrentIndex -ne $Local:ShouldBeAt) {
                Invoke-Debug "Moving row $Local:CurrentIndex to row $Local:ShouldBeAt";

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
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        # We have already re-ordered, and inserted new users, so now we just need to add a new column for the current month.
        [HashTable]$Local:EmailTable = Get-EmailToCell -WorkSheet $WorkSheet;
        $Local:EmailTable | Assert-NotNull -Message 'Email table was null';

        # Only insert new column if required.
        If ($AddNewData) {
            [String]$Local:NewColumnName = Get-Date -Format 'MMM-yy';
            [Int]$Local:NewColumnIndex = [Math]::Max(3, $WorkSheet.Dimension.Columns + 1);
            $WorkSheet.Cells[1, $Local:NewColumnIndex].Value = $Local:NewColumnName;

            # Set-ExcelColumn -Worksheet $WorkSheet `
            # -Column $Local:NewColumnIndex `
            # -AutoSize `
            # -Heading $Local:NewColumnName;
        }

        $LongestLineLength = 0;
        foreach ($Local:User in $NewData) {
            [String]$Local:Email = $Local:User.Email;
            [Int]$Local:Row = $Local:EmailTable[$Local:Email];

            if ($null -eq $Local:Row -or $Local:Row -eq 0) {
                Invoke-Verbose "$Local:Email doesn't exist in this sheet yet, skipping.";
                continue;
            }

            Invoke-Verbose "Updating row $Local:Row with new data";

            $WorkSheet.Cells[$Local:Row, 1].Value = $Local:User.DisplayName;
            $WorkSheet.Cells[$Local:Row, 2].Value = $Local:User.Email;

            If ($AddNewData) {
                $Local:Cell = $WorkSheet.Cells[$Local:Row, $Local:NewColumnIndex];

                $Cell.Value = $Local:User.MFA.Phone;
                # $Local:Cell.Value = $Local:User | Select-Object -ExcludeProperty Email, DisplayName | ConvertTo-FormattedToml;
                # $Cell.Style.WrapText = $true
                # $Local:Cell.Style.Numberformat.Format = '@';
                $Local:Cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::None;

                # $ThisLongestLineLength = $Local:Cell.Value -split "`n" | ForEach-Object { $_.Length } | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum;
                # if ($ThisLongestLineLength -gt $LongestLineLength) {
                #     $LongestLineLength = $ThisLongestLineLength;
                # }
            }
        }

        # if ($AddNewData) {
        #     Invoke-Info "Setting column width for column $Local:NewColumnIndex to $LongestLineLength";
        #     Set-ExcelColumn -Worksheet $WorkSheet `
        #         -Column $Local:NewColumnIndex `
        #         -Width $LongestLineLength;
        # }
    }
}

function Set-Check(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelWorksheet]$WorkSheet
) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $Local:LastColumn = $WorkSheet.Dimension.Columns;
        $Local:PrevColumn = $Local:LastColumn - 1;
        $Local:CurrColumn = $Local:LastColumn;
        $Local:CheckColumn = $Local:LastColumn + 1;

        if ($WorkSheet.Dimension.Columns -eq 4) {
            $Local:PrevColumn = $Local:LastColumn + 2;
        }

        foreach ($Local:Row in 2..$WorkSheet.Dimension.Rows) {
            $Local:Cell = $WorkSheet.Cells[$Local:Row, $Local:CheckColumn];
            # New Check Logic Follows
            if ($False) {
                $PreviousCellValue = $WorkSheet.Cells[$Local:Row, $Local:PrevColumn].Value

                if ($null -eq $PreviousCellValue) {
                    $Local:Cell.Value = 'No Previous';
                    $Local:Cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid;
                    $Local:Cell.Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::Yellow);
                    continue;
                }

                try {
                    $PreviousData = $PreviousCellValue | ConvertFrom-Toml;
                } catch {
                    # previous version data
                    $PreviousData = @{MFA = @{Phone = $PreviousCellValue } };
                }
                $CurrentCellValue = $WorkSheet.Cells[$Local:Row, $Local:CurrColumn].Value;
                if ($null -eq $CurrentCellValue) {
                    $Local:Cell.Value = 'No MFA';
                    $Local:Cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid;
                    $Local:Cell.Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::YellowGreen);
                    continue;
                }

                $CurrentData = $CurrentCellValue | ConvertFrom-Toml;

                $PrevKeys = $PreviousData.MFA.Keys;
                $CurrKeys = $CurrentData.MFA.Keys;
                $AllKeys = $PrevKeys + $CurrKeys | Sort-Object -Unique;

                $Local:ChangedValues = @();
                foreach ($Key in $AllKeys) {
                    $PrevValue = $PreviousData.MFA.$Key;
                    $CurrValue = $CurrentData.MFA.$Key;

                    if ($null -eq $PrevValue) {
                        $Local:ChangedValues += "+ $Key";
                    } elseif ($null -eq $CurrValue) {
                        $Local:ChangedValues += "- $Key";
                    } elseif ($PrevValue.GetType() -eq [Object[]]) {
                        $ValuesRemoved = $PrevValue | Where-Object { $CurrValue -notcontains $_ };
                        $ValuesAdded = $CurrValue | Where-Object { $PrevValue -notcontains $_ };
                        if ($ValuesRemoved.Count -gt 0) {
                            $Local:ChangedValues += "~- $Key $($ValuesRemoved -join ', ')";
                        }
                        if ($ValuesAdded.Count -gt 0) {
                            $Local:ChangedValues += "~+ $Key $($ValuesAdded -join ', ')";
                        }
                    } else {
                        $Local:ChangedValues += "~ $($Key): '$($PrevValue | ConvertTo-Json)' -> '$($CurrValue | ConvertTo-Json)'";
                    }
                }

                if ($ChangedValues.Count -gt 0) {
                    $Message = $ChangedValues -join "`r`n";
                    $MessageColour = [System.Drawing.Color]::Red;
                } else {
                    $Message = 'No changes';
                    $MessageColour = [System.Drawing.Color]::Green;
                }
            } else {
                [String]$Local:PrevNumber = $WorkSheet.Cells[$Local:Row, $Local:PrevColumn].Value;
                [String]$Local:CurrNumber = $WorkSheet.Cells[$Local:Row, $Local:CurrColumn].Value;
                ($Message, $MessageColour) = if ([String]::IsNullOrWhitespace($Local:PrevNumber) -and [String]::IsNullOrWhitespace($Local:CurrNumber)) {
                    'Missing',[System.Drawing.Color]::Turquoise;
                } elseif ([String]::IsNullOrWhitespace($Local:PrevNumber)) {
                    'No Previous',[System.Drawing.Color]::Yellow;
                } elseif ($Local:PrevNumber -eq $Local:CurrNumber) {
                    'Match',[System.Drawing.Color]::Green;
                } else {
                    'Mismatch',[System.Drawing.Color]::Red;
                }
            }

            $Local:Cell.Value = $Message;
            $Local:Cell.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid;
            $Local:Cell.Style.Fill.BackgroundColor.SetColor(($MessageColour));
        }

        $WorkSheet.Cells[1, $Local:CheckColumn].Value = 'Check';
    }
}

function Set-Styles(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelWorksheet]$WorkSheet
) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [String]$Local:LastColumn = $WorkSheet.Dimension.Address -split ':' | Select-Object -Last 1;
        [String]$Local:LastColumn = $Local:LastColumn -replace '[0-9]', '';

        Set-ExcelRange -Worksheet $WorkSheet -Range "A1:$($Local:LastColumn)1" -Bold -HorizontalAlignment Center;
        if ($WorkSheet.Dimension.Columns -ge 4) { Set-ExcelRange -Worksheet $WorkSheet -Range "D1:$($Local:LastColumn)1" -NumberFormat 'MMM-yy' };
        Set-ExcelRange -Worksheet $WorkSheet -Range "A2:$($Local:LastColumn)$(($WorkSheet.Dimension.Rows))" -AutoSize -ResetFont -BackgroundPattern Solid;
        # Set-ExcelRange -Worksheet $WorkSheet -Range "A2:$($lastColumn)$($WorkSheet.Dimension.Rows)"  # [System.Drawing.Color]::LightSlateGray
        # Set-ExcelRange -Worksheet $WorkSheet -Range "D2:$($lastColumn)$($WorkSheet.Dimension.Rows)" -NumberFormat "[<=9999999999]####-###-###;+(##) ###-###-###"
    }
}

function New-BaseWorkSheet(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelWorksheet]$WorkSheet
) {
    # Test if the worksheet has data by checking the dimension
    # If the dimension is null then there is no data
    if ($null -ne $WorkSheet.Dimension) {
        return
    }

    $WorkSheet.InsertColumn(1, 3)
    $WorkSheet.InsertRow(1, 1)

    $Local:Cells = $WorkSheet.Cells
    $Local:Cells[1, 1].Value = 'Name'
    $Local:Cells[1, 2].Value = 'Email'
    $Local:Cells[1, 3].Value = 'Phone'
}

function Get-ActiveWorkSheet(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelPackage]$ExcelData
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:ActiveWorkSheet; }

    process {
        [OfficeOpenXml.ExcelWorksheet]$Local:ActiveWorkSheet = $ExcelData.Workbook.Worksheets | Where-Object { $_.Name -eq 'Working' };
        if ($null -eq $Local:ActiveWorkSheet) {
            [OfficeOpenXml.ExcelWorksheet]$Local:ActiveWorkSheet = $ExcelData.Workbook.Worksheets.Add('Working')
        } else { $Local:ActiveWorkSheet.Name = 'Working' }

        # Move the worksheets to the correct position
        $ExcelData.Workbook.Worksheets.MoveToStart('Working')

        New-BaseWorkSheet -WorkSheet $Local:ActiveWorkSheet;

        return $Local:ActiveWorkSheet;
    }
}

function Get-HistoryWorkSheet(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [OfficeOpenXml.ExcelPackage]$ExcelData
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:HistoryWorkSheet; }

    process {
        [OfficeOpenXml.ExcelWorksheet]$Local:HistoryWorkSheet = $ExcelData.Workbook.Worksheets[2]
        if ($null -eq $HistoryWorkSheet -or $HistoryWorkSheet.Name -ne 'History') {
            Invoke-Info 'Creating new worksheet for history'
            $HistoryWorkSheet = $ExcelData.Workbook.Worksheets.Add('History')
        }

        # Move the worksheets to the correct position
        $ExcelData.Workbook.Worksheets.MoveAfter('History', 'Working')

        New-BaseWorkSheet -WorkSheet $Local:HistoryWorkSheet;

        return $Local:HistoryWorkSheet;
    }
}

function Save-Excel(
    [OfficeOpenXml.ExcelPackage]$ExcelData
) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        if ($ExcelData.Workbook.Worksheets.Count -gt 2) {
            Invoke-Info "Removing $($ExcelData.Workbook.Worksheets.Count - 2) worksheets";
            foreach ($Index in 3..$ExcelData.Workbook.Worksheets.Count) {
                $ExcelData.Workbook.Worksheets.Delete(3)
            }
        }

        Close-ExcelPackage $ExcelData -Show;
        # $ExcelData | Export-Excel "$Script:ExcelFile" -PassThru -AutoSize -FreezeTopRowFirstColumn
    }
}

function ConvertTo-FormattedToml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $Object
    )

    begin {
        $Regex = [Regex]::new('(?<=\s*=\s*\[)(?:("(?!").+(?!")",?)(?:\s*)?)+(?=\])');
    }

    process {
        $RawToml = $Object | ConvertTo-Toml -Depth 5;
        if ($null -eq $RawToml) {
            return $null;
        }

        while ($True) {
            $Match = $Regex.Match($RawToml);
            if (-not $Match.Success) {
                break;
            }

            $RawToml = $RawToml.Remove($Match.Index, $Match.Length);
            $ValueLines = $Match.Groups[1].Captures.Value -join "`n  ";
            $RawToml = $RawToml.Insert($Match.Index, "`n  " + $ValueLines + "`n");
        }

        return $RawToml;
    };
}

Invoke-RunMain $PSCmdlet {
    if (-not $ClientsFolder) {
        [String[]]$Local:PossiblePaths = @(
            "$env:USERPROFILE\AMT\Clients - Documents",
            "$env:USERPROFILE\OneDrive - AMT\Documents - Clients"
        );

        foreach ($Local:Path in $Local:PossiblePaths) {
            if (Test-Path $Local:Path) {
                [String]$Local:ClientsFolder = $Local:Path;
                break;
            }
        }

        if (-not $Local:ClientsFolder) {
            Invoke-Error 'Unable to find shared folder; please specify the full path to the shared folder.';
            return
        } else {
            Invoke-Info "Clients folder found at $Local:ClientsFolder";
        }
    }

    $Local:PossiblePaths = $Local:ClientsFolder | Get-ChildItem -Directory | Select-Object -ExpandProperty Name
    Invoke-Debug "Possible paths: $($Local:PossiblePaths -join ', ')"
    if (-not ($Local:PossiblePaths -contains $Client)) {
        $Local:PossibleMatches = $Local:PossiblePaths | Where-Object { $_ -like "$Client" }
        Invoke-Debug "Possible matches: $($Local:PossibleMatches -join ', ')"

        if ($Local:PossibleMatches -is [String]) {
            $Local:Client = $Local:PossibleMatches;
        } elseif ($Local:PossibleMatches.Count -eq 1) {
            $Local:Client = $Local:PossibleMatches[0]
        } elseif ($Local:PossibleMatches.Count -gt 1) {
            $Local:Client = Get-UserSelection `
                -Title 'Multiple client folders found' `
                -Question 'Please select the client you would like to run the script for' `
                -Choices $Local:PossibleMatches;
        } else {
            Invoke-Error "Client $Client not found; please check the spelling and try again."
            return
        }
    } else {
        $Local:Client = $Client;
    }

    [String]$Local:ClientFolder = "$ClientsFolder\$Local:Client";
    Invoke-Info "Client $Local:Client found at $Local:ClientFolder";

    Invoke-SetupEnvironment -Client $Local:Client -ClientsFolder $Local:ClientsFolder -ExcelFileName $ExcelFileName;

    [PSCustomObject[]]$Local:NewData = Get-CurrentData;
    [OfficeOpenXml.ExcelPackage]$Local:ExcelData = Get-Excel;

    [OfficeOpenXml.ExcelWorksheet]$Local:ActiveWorkSheet = Get-ActiveWorkSheet -ExcelData $Local:ExcelData;
    [OfficeOpenXml.ExcelWorksheet]$Local:HistoryWorkSheet = Get-HistoryWorkSheet -ExcelData $Local:ExcelData;
    $Local:ActiveWorkSheet | Assert-NotNull -Message 'ActiveWorkSheet was null';
    $Local:HistoryWorkSheet | Assert-NotNull -Message 'HistoryWorkSheet was null';

    Invoke-CleanupWorksheet -WorkSheet $Local:ActiveWorkSheet -DuplicateCheck;

    Invoke-CleanupWorksheet -WorkSheet $Local:HistoryWorkSheet -DuplicateCheck; # Dont check for duplicates in history, we want to preserve it.
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
