<#
.SYNOPSIS
    Used to print environment variables and other information within a N-Able ScriptRunner environment.
#>

Import-Module $PSScriptRoot/../common/00-Environment.psm1;
Invoke-RunMain $PSCmdlet {
    Invoke-Info 'Printing environment variables...'
    [Object[]]$Local:EnvironmentVariables = Get-ChildItem -Path 'env:';
    $Local:EnvironmentVariables | Format-Table -AutoSize -Wrap;

    Invoke-Info 'Printing console properties...'
    $Local:ConsoleProperties = @{
        'Console::Title'                    = [Console]::Title;
        'Host::Name'                        = $Host.Name;
        'Host::UI::SupportsVirtualTerminal' = $Host.UI.SupportsVirtualTerminal;
        'Host::UI::RawUI::WindowTitle'      = $Host.UI.RawUI.WindowTitle;
        'Host::UI::RawUI::WindowSize'       = $Host.UI.RawUI.WindowSize;
        'Host::UI::RawUI::BufferSize'       = $Host.UI.RawUI.BufferSize;
    };
    $Local:ConsoleProperties | Format-Table -AutoSize -Wrap;

    Invoke-Info 'Printing script properties...'
    $Local:ScriptProperties = @{
        'PSCommandPath' = $PSCommandPath
        'PSScriptRoot'  = $PSScriptRoot
        'CallingScript' = (Get-PSCallStack)[4].Command
    };
    $Local:ScriptProperties | Format-Table -AutoSize -Wrap;

    Invoke-Info 'Printing module properties...'
    $Local:Modules = Get-Module;
    $Local:Modules | Format-Table -AutoSize -Wrap;

    Invoke-Info 'Testing if is N-Able env';
    $Local:IsNable = ($Host.UI.RawUI.WindowTitle | Split-Path -Leaf) -eq 'fmplugin.exe';
    Invoke-Info "Is N-Able: $Local:IsNable";
    Invoke-Info "$($Host.UI.RawUI.WindowTitle | Split-Path -Leaf)";
};
