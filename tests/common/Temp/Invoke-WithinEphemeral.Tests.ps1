BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/Temp.psm1" }

Describe 'Invoke-WithinEphemeral Tests' {
    BeforeEach {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', $null)]
        $OriginalLocation = (Get-Location).Path
    }

    Context 'Basic Functionality' {
        It 'Should execute script block in temporary folder' {
            $Script:TempFolderPath = $null

            Invoke-WithinEphemeral {
                $Script:TempFolderPath = (Get-Location).Path
            }

            $TempFolderPath | Should -Not -BeNullOrEmpty
            $TempFolderPath | Should -Not -Be $OriginalLocation
        }

        It 'Should return to original location after execution' {
            Invoke-WithinEphemeral {
                'test' | Out-File 'testfile.txt'
            }

            (Get-Location).Path | Should -Be $OriginalLocation
        }

        It 'Should clean up temporary folder after execution' {
            $Script:TempFolderPath = $null

            Invoke-WithinEphemeral {
                $Script:TempFolderPath = (Get-Location).Path
                'test content' | Out-File 'testfile.txt'
                New-Item -ItemType Directory -Name 'subfolder'
            }

            Test-Path $Script:TempFolderPath | Should -Be $false
        }
    }

    Context 'Error Handling' {
        It 'Should clean up temporary folder even if script block throws an error' {
            $Script:TempFolderPath = $null

            { Invoke-WithinEphemeral {
                    $Script:TempFolderPath = (Get-Location).Path
                    'test content' | Out-File 'testfile.txt'
                    throw 'Test error'
                } } | Should -Throw 'Test error'

            Test-Path $Script:TempFolderPath | Should -Be $false
        }

        It 'Should return to original location even if script block throws an error' {
            { Invoke-WithinEphemeral {
                    throw 'Test error'
                } } | Should -Throw

            (Get-Location).Path | Should -Be $OriginalLocation
        }
    }

    Context 'Location Management' {
        It 'Should return to original location after Push-Location and Pop-Location Usage' {
            $Script:LocationStack = @()

            Invoke-WithinEphemeral {
                if ($env:TEMP) {
                    Push-Location $env:TEMP
                } else {
                    Push-Location '/tmp'
                }
            }

            (Get-Location).Path | Should -Be $OriginalLocation

            Invoke-WithinEphemeral {
                Pop-Location
            }

            (Get-Location).Path | Should -Be $OriginalLocation
        }
    }
}
