BeforeDiscovery { Import-Module -Name "$PSScriptRoot/../../../src/common/Logging.psm1" }
AfterAll { Remove-Module Logging -ErrorAction SilentlyContinue }

BeforeAll {
    function Get-ShouldBeString([String]$String) {
        $FixedString = $String -replace "`n", "`n+ ";

        InModuleScope Logging {
            if (Test-SupportsUnicode) {
                # There is an extra space at the end of the string
                $FixedString = " $FixedString"
            }
        }

        return $FixedString;
    }

    function Get-Stripped([Parameter(ValueFromPipeline)][String]$String) {
        # Replace all non-ASCII characters with a nothing string
        # Replace all ANSI escape sequences with a nothing string
        $String -replace '[^\u0000-\u007F]', '' -replace '\x1B\[[0-9;]*m', '';
    }

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
