[HashTable]$Script:WriteStyle = @{
    PSColour    = 'DarkCyan';
    PSPrefix    = '▶';
    ShouldWrite = $true;
};

function Clear-HostLight (
    [Parameter(Position = 1)]
    [int32]$Count = 1
) {
    $CurrentLine = $Host.UI.RawUI.CursorPosition.Y
    $ConsoleWidth = $Host.UI.RawUI.BufferSize.Width

    $i = 1
    for ($i; $i -le $Count; $i++) {
        [Console]::SetCursorPosition(0, ($CurrentLine - $i))
        [Console]::Write("{0,-$ConsoleWidth}" -f ' ')
    }

    [Console]::SetCursorPosition(0, ($CurrentLine - $Count))
}

function Register-ReadLineKeyHandlers {
    [Object]$Local:PreviousEnterFunction = (Get-PSReadLineKeyHandler -Chord Enter).Function;
    [Boolean]$Script:PressedEnter = $False;
    Set-PSReadLineKeyHandler -Chord Enter -ScriptBlock {
        Param([System.ConsoleKeyInfo]$Key, $Arg)

        $Script:PressedEnter = $True;
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine($Key, $Arg);
    };

    [Object]$Local:PreviousCtrlCFunction = (Get-PSReadLineKeyHandler -Chord Ctrl+c).Function;
    [Boolean]$Script:ShouldAbort = $False;
    Set-PSReadLineKeyHandler -Chord Ctrl+c -ScriptBlock {
        Param([System.ConsoleKeyInfo]$Key, $Arg)

        $Script:ShouldAbort = $True;
        [Microsoft.PowerShell.PSConsoleReadLine]::CancelLine($Key, $Arg);
    };

    return @{
        Enter = $Local:PreviousEnterFunction;
        CtrlC = $Local:PreviousCtrlCFunction;
    }
}

function Get-UserInput {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Title,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Question,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$Validate
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:UserInput; }

    process {
        Invoke-Write @Script:WriteStyle -PSMessage $Title;
        Invoke-Write @Script:WriteStyle -PSMessage $Question;

        [HashTable]$Local:PreviousFunctions = Register-ReadLineKeyHandlers;

        $Host.UI.RawUI.FlushInputBuffer();
        Clear-HostLight -Count 0; # Clear the line buffer to get rid of the >> prompt.
        Write-Host "`r>> " -NoNewline;

        do {
            [String]$Local:UserInput = [Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace, $ExecutionContext, $?);
            if (-not $Local:UserInput -or ($Validate -and (-not $Validate.InvokeReturnAsIs($Local:UserInput)))) {
                $Local:ClearLines = if ($Local:FailedAtLeastOnce -and $Script:PressedEnter) { 2 } else { 1 };
                Clear-HostLight -Count $Local:ClearLines;

                Invoke-Write @Script:WriteStyle -PSMessage 'Invalid input, please try again...';
                $Host.UI.Write('>> ');

                $Local:FailedAtLeastOnce = $true;
                $Script:PressedEnter = $false;
            } else {
                Clear-HostLight -Count 1;
                break;
            }
        } while (-not $Script:ShouldAbort);

        Set-PSReadLineKeyHandler -Chord Enter -Function $Local:PreviousFunctions.Enter;
        Set-PSReadLineKeyHandler -Chord Ctrl+c -Function $Local:PreviousFunctions.CtrlC;

        $Local:HistoryFile = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt";
        if (Test-Path -Path $Local:HistoryFile) {
            $Local:History = Get-Content -Path $Local:HistoryFile;
            $Local:History | Select-Object -First ($Local:History.Count - 1) | Set-Content -Path $Local:HistoryFile;
        }

        if ($Script:ShouldAbort) {
            throw [System.Management.Automation.PipelineStoppedException]::new();
        }

        return $Local:UserInput;
    }
}

function Get-UserConfirmation {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Title,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Question,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Boolean]$DefaultChoice
    )

    $Local:DefaultChoice = if ($null -eq $DefaultChoice) { 1 } elseif ($DefaultChoice) { 0 } else { 1 };
    $Local:Result = Get-UserSelection -Title $Title -Question $Question -Choices @('Yes', 'No') -DefaultChoice $Local:DefaultChoice;
    switch ($Local:Result) {
        0 { $true }
        Default { $false }
    }
}

function Get-UserSelection {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Title,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Question,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Array]$Choices,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Int]$DefaultChoice = 0
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Selection; }

    process {
        Invoke-Write @Script:WriteStyle -PSMessage $Title;
        Invoke-Write @Script:WriteStyle -PSMessage $Question;

        #region Setup PSReadLine Key Handlers
        $Local:PreviousTabFunction = (Get-PSReadLineKeyHandler -Chord Tab).Function;
        if (-not $Local:PreviousTabFunction) {
            $Local:PreviousTabFunction = 'TabCompleteNext';
        }

        $Script:ChoicesList = $Choices;
        Set-PSReadLineKeyHandler -Chord Tab -ScriptBlock {
            Param([System.ConsoleKeyInfo]$Key, $Arg)

            $Line = $null;
            $Cursor = $null;
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$Line, [ref]$Cursor);
            $MatchingInput = $Line.Substring(0, $Cursor);

            if ($Script:PreviewingChoices -and $Line -eq $Script:PreviewingInput) {
                if ($Script:ChoicesGoneThrough -eq $Script:MatchedChoices.Count - 1) {
                    $Script:ChoicesGoneThrough = 0;
                } else {
                    $Script:ChoicesGoneThrough++;
                }

                $Script:PreviewingInput = $Script:MatchedChoices[$Script:ChoicesGoneThrough];
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $MatchingInput.Length, $Script:PreviewingInput);
                return;
            }

            $Script:PreviewingChoices = $false;
            $Script:PreviewingInput = $null;
            $Script:ChoicesGoneThrough = 0;

            $Script:MatchedChoices = $Script:ChoicesList | Where-Object { $_ -like "$MatchingInput*" };

            if ($Script:MatchedChoices.Count -gt 1) {
                $Script:PreviewingChoices = $true;
                $Script:PreviewingInput = $Script:MatchedChoices[$Script:ChoicesGoneThrough];

                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $MatchingInput.Length, $Script:MatchedChoices[$Script:ChoicesGoneThrough]);
            } elseif ($Script:MatchedChoices.Count -eq 1) {
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $MatchingInput.Length, $Script:MatchedChoices);
            }
        }

        $Local:PreviousEnterFunction = (Get-PSReadLineKeyHandler -Chord Enter).Function;
        $Script:PressedEnter = $false;
        Set-PSReadLineKeyHandler -Chord Enter -ScriptBlock {
            Param([System.ConsoleKeyInfo]$Key, $Arg)

            $Script:PressedEnter = $true;
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine($Key, $Arg);
        };

        $Local:PreviousCtrlCFunction = (Get-PSReadLineKeyHandler -Chord Ctrl+c).Function;
        $Script:ShouldAbort = $false;
        Set-PSReadLineKeyHandler -Chord Ctrl+c -ScriptBlock {
            Param([System.ConsoleKeyInfo]$Key, $Arg)

            $Script:ShouldAbort = $true;
            [Microsoft.PowerShell.PSConsoleReadLine]::CancelLine($Key, $Arg);
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine($Key, $Arg);
        };
        #endregion

        [Boolean]$Local:FirstRun = $true;
        $Host.UI.RawUI.FlushInputBuffer();
        Clear-HostLight -Count 0; # Clear the line buffer to get rid of the >> prompt.
        Invoke-Write @Script:WriteStyle -PSMessage "Enter one of the following: $($Choices -join ', ')";
        Write-Host ">> $($PSStyle.Foreground.FromRgb(40, 44, 52))$($Choices[$DefaultChoice])" -NoNewline;
        Write-Host "`r>> " -NoNewline;

        do {
            $Local:Selection = [Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace, $ExecutionContext, $?);

            if (-not $Local:Selection -and $Local:FirstRun) {
                $Local:Selection = $Choices[$DefaultChoice];
                Clear-HostLight -Count 1;
            } elseif ($Local:Selection -notin $Choices) {
                $Local:ClearLines = if ($Local:FailedAtLeastOnce -and $Script:PressedEnter) { 2 } else { 1 };
                Clear-HostLight -Count $Local:ClearLines;

                Invoke-Write @Script:WriteStyle -PSMessage 'Invalid selection, please try again...';
                $Host.UI.Write('>> ');

                $Local:FailedAtLeastOnce = $true;
                $Script:PressedEnter = $false;
            }

            $Local:FirstRun = $false;
        } while ($Local:Selection -notin $Choices -and -not $Script:ShouldAbort);

        Set-PSReadLineKeyHandler -Chord Tab -Function $Local:PreviousTabFunction;
        Set-PSReadLineKeyHandler -Chord Enter -Function $Local:PreviousEnterFunction;
        Set-PSReadLineKeyHandler -Chord Ctrl+c -Function $Local:PreviousCtrlCFunction;

        if ($Script:ShouldAbort) {
            throw [System.Management.Automation.PipelineStoppedException]::new();
        }

        return $Choices.IndexOf($Local:Selection);
    }
}

function Get-PopupSelection {
    Param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [String]$Title = 'Select a(n) Item',

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Object[]]$Items,

        [Parameter()]
        [switch]$AllowNone
    )

    $Local:Selection;
    while (-not $Local:Selection) {
        $Local:Selection = $Items | Out-GridView -Title $Title -PassThru;
        if ((-not $AllowNone) -and (-not $Local:Selection)) {
            Invoke-Info "No Item was selected, re-running selection...";
        }
    }

    $Local:Selection -and -not $AllowNone | Assert-NotNull -Message "Failed to select a $ItemName.";
    return $Local:Selection;
}

Export-ModuleMember -Function Get-UserInput, Get-UserConfirmation, Get-UserSelection, Get-PopupSelection;
