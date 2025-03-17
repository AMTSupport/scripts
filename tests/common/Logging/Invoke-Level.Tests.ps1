BeforeDiscovery {
    Import-Module -Name "$PSScriptRoot/../../../src/common/Logging.psm1"
    Import-Module -Name "$PSScriptRoot/Helpers.psm1"
}

BeforeAll {
    $Params = @{
        Message   = 'Test message'
    };
}

Describe 'Invoke-Level Tests' {
    It 'Invoke-<Function> should write when <Preference> is <Level>' {
        Set-Variable -Name $Preference -Value $Level
        & Invoke-$Function -InformationVariable Output @Params;
        $Output | Select-Object -First 1 | Get-Stripped | Should -Be (Get-ShouldBeString $Params.Message);
    } -ForEach @(
        @{ Function = 'Verbose'; Preference = 'VerbosePreference'; Level = 'Continue'; },
        @{ Function = 'Debug'; Preference = 'DebugPreference'; Level = 'Continue'; },
        @{ Function = 'Warn'; Preference = 'WarningPreference'; Level = 'Continue'; },
        @{ Function = 'Info'; Preference = 'InformationPreference'; Level = 'Continue'; },
        @{ Function = 'Info'; Preference = 'InformationPreference'; Level = 'SilentlyContinue'; }, # By default info is silently continue which is dumb.
        @{ Function = 'Error'; Preference = 'ErrorActionPreference'; Level = 'Continue'; }
    )

    It 'Invoke-<Function> should not write when <Preference> is <Level>' {
        Set-Variable -Name $Preference -Value $Level
        & Invoke-$Function -InformationVariable Output @Params;
        $Output | Select-Object -First 1 | Should -Be $null;
    } -ForEach @(
        @{ Function = 'Verbose'; Preference = 'VerbosePreference'; Level = 'SilentlyContinue'; },
        @{ Function = 'Verbose'; Preference = 'VerbosePreference'; Level = 'Ignore'; },
        @{ Function = 'Debug'; Preference = 'DebugPreference'; Level = 'SilentlyContinue'; },
        @{ Function = 'Debug'; Preference = 'DebugPreference'; Level = 'Ignore'; },
        @{ Function = 'Warn'; Preference = 'WarningPreference'; Level = 'SilentlyContinue'; },
        @{ Function = 'Warn'; Preference = 'WarningPreference'; Level = 'Ignore'; },
        @{ Function = 'Info'; Preference = 'InformationPreference'; Level = 'Ignore'; },
        @{ Function = 'Error'; Preference = 'ErrorActionPreference'; Level = 'SilentlyContinue'; },
        @{ Function = 'Error'; Preference = 'ErrorActionPreference'; Level = 'Ignore'; }
    )
}
