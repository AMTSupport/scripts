function Invoke-WithColour {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]$ScriptBlock
    )

    $Local:UI = $Host.UI.RawUI;
    $Local:PrevForegroundColour = $Local:UI.ForegroundColor;
    $Local:PrevBackgroundColour = $Local:UI.BackgroundColor;

    $Local:UI.ForegroundColor = 'Yellow';
    $Local:UI.BackgroundColor = 'Black';

    $Local:Return = & $ScriptBlock

    $Local:UI.ForegroundColor = $Local:PrevForegroundColour;
    $Local:UI.BackgroundColor = $Local:PrevBackgroundColour;

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

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Boolean]$DefaultChoice
    )

    $Local:DefaultChoice = if ($DefaultChoice) { 0 } else { 1 }
    $Local:Result = Get-UserSelection -Title $Title -Question $Question -Choices @('&Yes', '&No') -DefaultChoice $Local:DefaultChoice
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

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Int]$DefaultChoice
    )

    return Invoke-WithColour {
        Write-Host -ForegroundColor DarkCyan $Title;
        Write-Host -ForegroundColor DarkCyan "$($Question): " -NoNewline;

        $Host.UI.RawUI.FlushInputBuffer();
        return $Host.UI.PromptForChoice('', '', $Choices, $DefaultChoice);
    }
}

Export-ModuleMember -Function Get-UserInput, Get-UserConfirmation, Get-UserSelection;
