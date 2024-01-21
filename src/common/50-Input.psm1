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
    $Local:Result = Get-UserSelection -Title $Title -Question $Question -Choices @('&Yes', '&No') -DefaultChoice $Local:DefaultChoice;
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

        $Host.UI.RawUI.FlushInputBuffer();
        return $Host.UI.PromptForChoice('', '', $Choices, $DefaultChoice);
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
