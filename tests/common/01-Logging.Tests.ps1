BeforeDiscovery {
    $ModuleName = & $PSScriptRoot/Base.ps1;
}

AfterAll {
    Remove-CommonModules;
}

BeforeAll {
    function Get-ShouldBeString([String]$String) {
        $String -replace "`n", "`n+ ";
    }

    function Get-Stripped([Parameter(ValueFromPipeline)][String]$String) {
        # Replace all non-ASCII characters with a nothing string
        # Replace all ANSI escape sequences with a nothing string
        $String -replace '[^\u0000-\u007F]', '' -replace '\x1B\[[0-9;]*m', ''
    }
}

Describe 'Logging Tests' {
    # TODO
    Context 'Unicode & Colour Support' {

    }

    Context 'Invoke-Write' {
        It 'Should not write anything if $ShouldWrite is $false' {
            @{
                PSMessage   = 'Test message'
                PSColour    = 'Green'
                ShouldWrite = $false
            } | Invoke-Write -InformationVariable Output;

            $Output | Select-Object -First 1 | Should -Be $null;
        }

        It 'Should write the message if $ShouldWrite is $true' {
            $Params = @{
                PSMessage   = 'Test message'
                PSColour    = 'Green'
                ShouldWrite = $true
            };

            $Params | Invoke-Write -InformationVariable Output;
            $Output | Select-Object -First 1 | Get-Stripped | Should -Be (Get-ShouldBeString $Params.PSMessage);
        }

        It 'Should replace newline characters in the message' {
            $Params = @{
                PSMessage   = "Test message`nSecond line"
                PSColour    = 'Green'
                ShouldWrite = $true
            };

            $Params | Invoke-Write -InformationVariable Output;
            $Output | Select-Object -First 1  | Get-Stripped | Should -Be (Get-ShouldBeString $Params.PSMessage);
        }
    }

    Context 'Invoke-Info' {
        It 'Should write when $Global:Logging.Information is $true' {
            $Global:Logging.Information = $true;
            $Params = @{
                Message   = 'Test message'
            };

            $Params | Invoke-Info -InformationVariable Output;
            $Output | Select-Object -First 1 | Get-Stripped | Should -Be (Get-ShouldBeString $Params.Message);
        }

        It 'Should not write when $Global:Logging.Information is $false' {
            $Global:Logging.Information = $false;
            $Params = @{
                Message   = 'Test message'
            };

            $Params | Invoke-Info -InformationVariable Output;
            $Output | Select-Object -First 1 | Should -Be $null;
        }
    }

    Context 'Invoke-Verbose' {
        It 'Should write when $Global:Logging.Verbose is $true' {
            $Global:Logging.Verbose = $true;
            $Params = @{
                Message   = 'Test message'
            };

            $Params | Invoke-Verbose -InformationVariable Output;
            $Output | Select-Object -First 1 | Get-Stripped | Should -Be (Get-ShouldBeString $Params.Message);
        }

        It 'Should not write when $Global:Logging.Verbose is $false' {
            $Global:Logging.Verbose = $false;
            $Params = @{
                Message   = 'Test message'
            };

            $Params | Invoke-Verbose -InformationVariable Output;
            $Output | Select-Object -First 1 | Should -Be $null;
        }
    }

    Context 'Invoke-Debug' {
        It 'Should write when $Global:Logging.Debug is $true' {
            $Global:Logging.Debug = $true;
            $Params = @{
                Message   = 'Test message'
            };

            $Params | Invoke-Debug -InformationVariable Output;
            $Output | Select-Object -First 1 | Get-Stripped | Should -Be (Get-ShouldBeString $Params.Message);
        }

        It 'Should not write when $Global:Logging.Debug is $false' {
            $Global:Logging.Debug = $false;
            $Params = @{
                Message   = 'Test message'
            };

            $Params | Invoke-Debug -InformationVariable Output;
            $Output | Select-Object -First 1 | Should -Be $null;
        }
    }

    Context 'Invoke-Error' {
        It 'Should write when $Global:Logging.Error is $true' {
            $Global:Logging.Error = $true;
            $Params = @{
                Message   = 'Test message'
            };

            $Params | Invoke-Error -InformationVariable Output;
            $Output | Select-Object -First 1 | Get-Stripped | Should -Be (Get-ShouldBeString $Params.Message);
        }

        It 'Should not write when $Global:Logging.Error is $false' {
            $Global:Logging.Error = $false;
            $Params = @{
                Message   = 'Test message'
            };

            $Params | Invoke-Error -InformationVariable Output;
            $Output | Select-Object -First 1 | Should -Be $null;
        }
    }

    Context 'Invoke-Warn' {
        It 'Should write when $Global:Logging.Warning is $true' {
            $Global:Logging.Warning = $true;
            $Params = @{
                Message   = 'Test message'
            };

            $Params | Invoke-Warn -InformationVariable Output;
            $Output | Select-Object -First 1 | Get-Stripped | Should -Be (Get-ShouldBeString $Params.Message);
        }

        It 'Should not write when $Global:Logging.Warning is $false' {
            $Global:Logging.Warning = $false;
            $Params = @{
                Message   = 'Test message'
            };

            $Params | Invoke-Warn -InformationVariable Output;
            $Output | Select-Object -First 1 | Should -Be $null;
        }
    }


}
