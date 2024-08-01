Using module ./00-Utils.psm1
Using module ./01-Logging.psm1
Using module ./01-Scope.psm1
Using module ./05-Assert.psm1
Using module ./05-Ensure.psm1
Using module @{
    ModuleName    = 'PSReadLine';
    ModuleVersion = '2.3.2';
}

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

        Invoke-Info 'Ctrl+C was pressed, aborting...';
        $Script:ShouldAbort = $True;
        [Microsoft.PowerShell.PSConsoleReadLine]::CancelLine($Key, $Arg);
    };

    [Int]$Script:ExtraLines = 0;
    [ScriptBlock]$Private:EnterScriptBlock = {
        Param([System.ConsoleKeyInfo]$Key, $Arg)

        $Script:ExtraLines++;
        [Microsoft.PowerShell.PSConsoleReadLine]::AddLine($Key, $Arg);
    };

    [Object]$Local:PreviousCtrlEnterFunction = (Get-PSReadLineKeyHandler -Chord Ctrl+Enter).Function;
    [Object]$Local:PreviousShiftEnterFunction = (Get-PSReadLineKeyHandler -Chord Shift+Enter).Function;
    Set-PSReadLineKeyHandler -Chord Ctrl+Enter -ScriptBlock $Private:EnterScriptBlock;
    Set-PSReadLineKeyHandler -Chord Shift+Enter -ScriptBlock $Private:EnterScriptBlock;

    [System.Func[String, Object]]$Local:HistoryHandler = (Get-PSReadLineOption).AddToHistoryHandler;
    if ($DontSaveInputs) {
        Set-PSReadLineOption -AddToHistoryHandler {
            Param([String]$Line)

            $False;
        }
    }

    return @{
        Enter          = $Local:PreviousEnterFunction;
        CtrlC          = $Local:PreviousCtrlCFunction;
        CtrlShift      = $Local:PreviousCtrlEnterFunction;
        ShiftEnter     = $Local:PreviousShiftEnterFunction;
        HistoryHandler = $Local:HistoryHandler;
    }
}

function Unregister-CustomReadLineHandlers([HashTable]$PreviousHandlers) {
    Set-PSReadLineKeyHandler -Chord Enter -Function $PreviousHandlers.Enter;
    Set-PSReadLineKeyHandler -Chord Ctrl+c -Function $PreviousHandlers.CtrlC;
    Set-PSReadLineKeyHandler -Chord Ctrl+Enter -Function $PreviousHandlers.CtrlShift;
    Set-PSReadLineKeyHandler -Chord Shift+Enter -Function $PreviousHandlers.ShiftEnter;
    Set-PSReadLineOption -AddToHistoryHandler $PreviousHandlers.HistoryHandler;
}

<#
.SYNOPSIS
    Prompts the user for input.

.DESCRIPTION
    Prompts the user for input, with the ability to validate the input and return it as a SecureString.
    If the input is invalid, the user will be prompted to try again.

.PARAMETER Title
    The title of the prompt.

.PARAMETER Question
    The question to ask the user.

.PARAMETER Validate
    A script block to validate the user input.
    The script block is invoked with the raw string the user entered.

.PARAMETER AsSecureString
    If set, the user input will be returned as a SecureString.
    This setting implies DontSaveInputs.

.PARAMETER DontSaveInputs
    If set, the user input will not be saved in the history.

.PARAMETER SaveInputAsUniqueHistory
    If set, the user input will be saved as a unique history item.
    This will result in a history file being made which is only avaialble when this exact
    Get-UserInput function is called, this is done by combining the title and question and hashing it.

    When this is set, the input will not be saved to normal history and the user will only be able to
    use the up and down arrow keys to navigate through the history of this specific prompt.

.EXAMPLE
    ```
    Get-UserInput `
        -Title 'Enter your name' `
        -Question 'What is your name?' `
        -Validate { Param([String]$Input) $Input.Length -gt 0; }
    ```

    This will prompt the user with the title "Enter your name" and the question "What is your name?".

.EXAMPLE
    ```
    Get-UserInput `
        -Title 'Enter your password' `
        -Question 'What is your password?' `
        -AsSecureString
    ```

    This will prompt the user with the title "Enter your password" and the question "What is your password?".
    The user input will be returned as a SecureString.
#>
function Get-UserInput {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Title,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Alias('Prompt')]
        [String]$Question,

        [Parameter(HelpMessage = 'Validation script block to validate the user input.')]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$Validate,

        [Parameter()]
        [Switch]$AsSecureString,

        [Parameter()]
        [Switch]$DontSaveInputs = $AsSecureString,

        [Parameter()]
        [Switch]$SaveInputAsUniqueHistory,

        [Parameter()]
        [Switch]$AllowEmpty
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:UserInput; }

    process {
        Invoke-Write @Script:WriteStyle -PSMessage $Title;
        Invoke-Write @Script:WriteStyle -PSMessage $Question;

        [HashTable]$Local:PreviousFunctions = Register-CustomReadLineHandlers -DontSaveInputs:$DontSaveInputs;
        if ($SaveInputAsUniqueHistory) {
            $Local:PreviousHistorySavePath = (Get-PSReadLineOption).HistorySavePath;

            $Local:Hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes("$Title$Question"));
            $Local:HashString = [System.BitConverter]::ToString($Local:Hash).Replace('-', '');
            $Local:HashString = $Local:HashString.Substring(0, [Math]::Min(8, $Local:HashString.Length));
            $Private:FileLocation = "$env:APPDATA\Roaming\Microsoft\Windows\PowerShell\PSReadLine\UniqueHistory-$Local:HashString.txt";
            Set-PSReadLineOption -HistorySavePath $Private:FileLocation;
        }

        $Host.UI.RawUI.FlushInputBuffer();
        Clear-HostLight -Count 0; # Clear the line buffer to get rid of the >> prompt.
        Write-Host "`r>> " -NoNewline;

        do {
            [String]$Local:UserInput = ([Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace, $ExecutionContext, $?)).Trim();
            if ((-not $AllowEmpty -and -not $Local:UserInput) -or ($Validate -and (-not $Validate.InvokeWithContext($null, [PSVariable]::new('_', $Local:UserInput))))) {
                $Local:ClearLines = if ($Local:FailedAtLeastOnce -and $Script:PressedEnter) {
                    $Private:Value = $Script:ExtraLines + 2;
                    $Script:ExtraLines = 0;
                    $Private:Value;
                } else {
                    1
                };

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

        if ($SaveInputAsUniqueHistory) {
            Set-PSReadLineOption -HistorySavePath $Local:PreviousHistorySavePath;
        }

        if ($AllowEmpty -and -not $Local:UserInput) {
            return $null;
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
        [Int]$DefaultChoice = 0,

        [Parameter()]
        [Switch]$AllowNone,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$FormatChoice = { Param([String]$Choice) $Choice.ToString(); }
    )

    begin {
        Enter-Scope;

        [Console]::TreatControlCAsInput = $True;

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
            if (-not $Formatted -or $Formatted -eq '') {
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
    }

    process {
        Invoke-Write @Script:WriteStyle -PSMessage $Title;
        Invoke-Write @Script:WriteStyle -PSMessage $Question;

        [Boolean]$Local:FirstRun = $true;
        $Host.UI.RawUI.FlushInputBuffer();
        Clear-HostLight -Count 0; # Clear the line buffer to get rid of the >> prompt.
        Invoke-Write @Script:WriteStyle -PSMessage "Enter one of the following: $($ChoicesList -join ', ')";
        Write-Host '>> ' -NoNewline;
        if ($null -ne $DefaultChoice) {
            Write-Host "$($PSStyle.Foreground.FromRgb(40, 44, 52))$($ChoicesList[$DefaultChoice])" -NoNewline;
        }
        Write-Host "`r>> " -NoNewline;

        do {
            if ([Console]::KeyAvailable) {
                $Key = [Console]::ReadKey($True);
                if ($Key.Modifiers -eq 'Control' -and $Key.Key -eq 'C') {
                    Invoke-Info 'Ctrl+C was pressed, aborting...';
                    $Script:ShouldAbort = $True;
                    break;
                }
            }
            $Local:Selection = ([Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace, $ExecutionContext, $?)).Trim();

            if (-not $Local:Selection -and $Local:FirstRun -and $null -ne $DefaultChoice) {
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

        if ($Script:ShouldAbort) {
            if (-not $AllowNone) {
                throw [System.Management.Automation.PipelineStoppedException]::new();
            } else {
                return $null;
            }
        }

        return $Choices[$ChoicesList.IndexOf($Local:Selection)];
    }

    end {
        Exit-Scope -ReturnValue $Local:Selection;

        if ($Local:PreviousTabFunction -ne 'CustomAction') { Set-PSReadLineKeyHandler -Chord Tab -Function $Local:PreviousTabFunction; }
        if ($Local:PreviousShiftTabFunction -ne 'CustomAction') { Set-PSReadLineKeyHandler -Chord Shift+Tab -Function $Local:PreviousShiftTabFunction; }
        if ($Local:PreviousFunctions) { Unregister-CustomReadLineHandlers -PreviousHandlers $Local:PreviousFunctions; }
        [Console]::TreatControlCAsInput = $False;
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
            Invoke-Info 'No Item was selected, re-running selection...';
        }
    }

    $Local:Selection -and -not $AllowNone | Assert-NotNull -Message "Failed to select a $ItemName.";
    return $Local:Selection;
}

Export-ModuleMember -Function Get-UserInput, Get-UserConfirmation, Get-UserSelection, Get-PopupSelection -Variable Validations;
