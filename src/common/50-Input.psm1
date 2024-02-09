Function Clear-HostLight (
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

function Invoke-WithColour {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$ScriptBlock
    )

    try {
        $Local:UI = $Host.UI.RawUI;
        $Local:PrevForegroundColour = $Local:UI.ForegroundColor;
        $Local:PrevBackgroundColour = $Local:UI.BackgroundColor;

        $Local:UI.ForegroundColor = 'Yellow';
        $Local:UI.BackgroundColor = 'Black';

        $Local:Return = & $ScriptBlock
    } finally {
        $Local:UI.ForegroundColor = $Local:PrevForegroundColour;
        $Local:UI.BackgroundColor = $Local:PrevBackgroundColour;
    }

    return $Local:Return;
}

function Get-UserInput {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Title,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Question
    )

    return Invoke-WithColour {
        Write-Host -ForegroundColor DarkCyan $Title;
        Write-Host -ForegroundColor DarkCyan "$($Question): " -NoNewline;

        # Clear line buffer to not get old input.
        $Host.UI.RawUI.FlushInputBuffer();
        return $Host.UI.ReadLine();
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

    return Invoke-WithColour {
        [HashTable]$Local:BaseFormat = @{
            PSColour    = 'DarkCyan';
            PSPrefix    = '▶';
            ShouldWrite = $true;
        };

        Invoke-Write @Local:BaseFormat -PSMessage $Title;
        Invoke-Write @Local:BaseFormat -PSMessage $Question;

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

        $Local:FirstRun = $true;
        $Host.UI.RawUI.FlushInputBuffer();
        Clear-HostLight -Count 0; # Clear the line buffer to get rid of the >> prompt.
        Invoke-Write @Local:BaseFormat -PSMessage "Enter one of the following: $($Choices -join ', ')";
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

                Invoke-Write @Local:BaseFormat -PSMessage "Invalid selection, please try again...";
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
