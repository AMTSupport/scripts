$Script:Validations = @{
    Email = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
}

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

function Register-CustomReadLineHandlers([Switch]$DontSaveInputs) {
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

    [System.Func[String,Object]]$Local:HistoryHandler = (Get-PSReadLineOption).AddToHistoryHandler;
    if ($DontSaveInputs) {
        Set-PSReadLineOption -AddToHistoryHandler {
            Param([String]$Line)

            $False;
        }
    }

    return @{
        Enter           = $Local:PreviousEnterFunction;
        CtrlC           = $Local:PreviousCtrlCFunction;
        HistoryHandler  = $Local:HistoryHandler;
    }
}

function Unregister-CustomReadLineHandlers([HashTable]$PreviousHandlers) {
    Set-PSReadLineKeyHandler -Chord Enter -Function $PreviousHandlers.Enter;
    Set-PSReadLineKeyHandler -Chord Ctrl+c -Function $PreviousHandlers.CtrlC;
    Set-PSReadLineOption -AddToHistoryHandler $PreviousHandlers.HistoryHandler;
}

# TODO - Better SecureString handling.
function Get-UserInput {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Title,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Question,

        [Parameter(HelpMessage = 'Validation script block to validate the user input.')]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$Validate,

        [Parameter()]
        [Switch]$AsSecureString,

        [Parameter()]
        [Switch]$DontSaveInputs
    )

    begin { Enter-Scope; Install-Requirements; }
    end { Exit-Scope -ReturnValue $Local:UserInput; }

    process {
        Invoke-Write @Script:WriteStyle -PSMessage $Title;
        Invoke-Write @Script:WriteStyle -PSMessage $Question;

        [HashTable]$Local:PreviousFunctions = Register-CustomReadLineHandlers -DontSaveInputs:($DontSaveInputs -or $AsSecureString);

        $Host.UI.RawUI.FlushInputBuffer();
        Clear-HostLight -Count 0; # Clear the line buffer to get rid of the >> prompt.
        Write-Host "`r>> " -NoNewline;

        do {
            [String]$Local:UserInput = ([Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace, $ExecutionContext, $?)).Trim();
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

        Unregister-CustomReadLineHandlers -PreviousHandlers $Local:PreviousFunctions;

        if ($Script:ShouldAbort) {
            throw [System.Management.Automation.PipelineStoppedException]::new();
        }

        if ($AsSecureString) {
            [SecureString]$Local:UserInput = ConvertTo-SecureString -String $Local:UserInput -AsPlainText -Force;
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
        'Yes' { $true }
        'No' { $false }
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
        [Alias('Items')]
        [Array]$Choices,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Int]$DefaultChoice = 0,

        [Parameter()]
        [Switch]$AllowNone,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$FormatChoice = { Param([String]$Choice) $Choice.ToString(); }
    )

    begin { Enter-Scope; Install-Requirements; }
    end { Exit-Scope -ReturnValue $Local:Selection; }

    process {
        Invoke-Write @Script:WriteStyle -PSMessage $Title;
        Invoke-Write @Script:WriteStyle -PSMessage $Question;

        #region Setup PSReadLine Key Handlers
        [HashTable]$Local:PreviousFunctions = Register-CustomReadLineHandlers -DontSaveInputs;

        $Local:PreviousTabFunction = (Get-PSReadLineKeyHandler -Chord Tab).Function;
        if (-not $Local:PreviousTabFunction) {
            $Local:PreviousTabFunction = 'TabCompleteNext';
        }
        $Local:PreviousShiftTabFunction = (Get-PSReadLineKeyHandler -Chord Shift+Tab).Function;
        if (-not $Local:PreviousShiftTabFunction) {
            $Local:PreviousShiftTabFunction = 'TabCompletePrevious';
        }

        [String[]]$Script:ChoicesList = $Choices | ForEach-Object {
            $Formatted = $FormatChoice.InvokeReturnAsIs($_);
            if (-not $Formatted -or $Formatted -eq "") {
                throw [System.ArgumentException]::new('FormatChoice script block must return a non-empty string.');
            }

            $Formatted;
        };
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
        Set-PSReadLineKeyHandler -Chord Shift+Tab -ScriptBlock {
            Param([System.ConsoleKeyInfo]$Key, $Arg)

            $Line = $null;
            $Cursor = $null;
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$Line, [ref]$Cursor);
            $MatchingInput = $Line.Substring(0, $Cursor);

            if ($Script:PreviewingChoices -and $Line -eq $Script:PreviewingInput) {
                if ($Script:ChoicesGoneThrough -eq 0) {
                    $Script:ChoicesGoneThrough = $Script:MatchedChoices.Count - 1;
                } else {
                    $Script:ChoicesGoneThrough--;
                }

                $Script:PreviewingInput = $Script:MatchedChoices[$Script:ChoicesGoneThrough];
                [Microsoft.PowerShell.PSConsoleReadLine]::Replace(0, $MatchingInput.Length, $Script:PreviewingInput);
                return;
            }
        };
        #endregion

        [Boolean]$Local:FirstRun = $true;
        $Host.UI.RawUI.FlushInputBuffer();
        Clear-HostLight -Count 0; # Clear the line buffer to get rid of the >> prompt.
        Invoke-Write @Script:WriteStyle -PSMessage "Enter one of the following: $($ChoicesList -join ', ')";
        Write-Host ">> $($PSStyle.Foreground.FromRgb(40, 44, 52))$($ChoicesList[$DefaultChoice])" -NoNewline;
        Write-Host "`r>> " -NoNewline;

        do {
            $Local:Selection = ([Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace, $ExecutionContext, $?)).Trim();

            if (-not $Local:Selection -and $Local:FirstRun) {
                $Local:Selection = $Choices[$DefaultChoice];
                Clear-HostLight -Count 1;
            } elseif ($Local:Selection -notin $ChoicesList) {
                $Local:ClearLines = if ($Local:FailedAtLeastOnce -and $Script:PressedEnter) { 2 } else { 1 };
                Clear-HostLight -Count $Local:ClearLines;

                Invoke-Write @Script:WriteStyle -PSMessage 'Invalid selection, please try again...';
                $Host.UI.Write('>> ');

                $Local:FailedAtLeastOnce = $true;
                $Script:PressedEnter = $false;
            }

            $Local:FirstRun = $false;
        } while ($Local:Selection -notin $ChoicesList -and -not $Script:ShouldAbort);

        Set-PSReadLineKeyHandler -Chord Tab -Function $Local:PreviousTabFunction;
        Set-PSReadLineKeyHandler -Chord Shift+Tab -Function $Local:PreviousShiftTabFunction;
        Unregister-CustomReadLineHandlers -PreviousHandlers $Local:PreviousFunctions;

        if ($Script:ShouldAbort) {
            if (-not $AllowNone) {
                throw [System.Management.Automation.PipelineStoppedException]::new();
            } else {
                return $null;
            }
        }

        return $Choices[$ChoicesList.IndexOf($Local:Selection)];
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

# TODO :: Make a common way to handle requirements.
[Boolean]$Script:CompletedSetup = $False;
function Install-Requirements {
    if ($Script:CompletedSetup) {
        return;
    }

    # Windows comes pre-installed with PSReadLine 2.0.0, so we need to ensure that we have at least 2.3.0;
    Invoke-EnsureModule @{
        Name           = 'PSReadLine';
        MinimumVersion = '2.3.0';
        DontRemove     = $True;
    };

    $Using = [ScriptBlock]::Create('Using module ''PSReadLine''');
    . $Using;

    [Boolean]$Script:CompletedSetup = $True;
}

try {
    Install-Requirements;
} catch {
    throw $_;
}

Export-ModuleMember -Function Get-UserInput, Get-UserConfirmation, Get-UserSelection, Get-PopupSelection -Variable Validations;
