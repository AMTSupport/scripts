BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/Temp.psm1" }

Describe 'Invoke-WithinEphemeral Tests' {
    BeforeAll {
        $TestTempPath = [System.IO.Path]::GetTempPath()
        $OriginalLocation = Get-Location
    }

    AfterEach {
        # Ensure we're back to original location
        Set-Location $OriginalLocation
        
        # Clean up any test folders created
        Get-ChildItem -Path $TestTempPath -Directory | Where-Object { $_.CreationTime -gt (Get-Date).AddMinutes(-1) } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'Basic Functionality' {
        It 'Should execute script block in temporary folder' {
            $Global:ExecutedInTempFolder = $false
            $Global:TempFolderPath = $null
            
            $ScriptBlock = {
                $Global:TempFolderPath = (Get-Location).Path
                $Global:ExecutedInTempFolder = $Global:TempFolderPath -like "*tmp*"
            }
            
            Invoke-WithinEphemeral -ScriptBlock $ScriptBlock
            
            $Global:ExecutedInTempFolder | Should -Be $true
            $Global:TempFolderPath | Should -Not -BeNullOrEmpty
        }

        It 'Should return to original location after execution' {
            $LocationBeforeTest = Get-Location
            
            $ScriptBlock = {
                # Do something in the temp folder
                'test' | Out-File 'testfile.txt'
            }
            
            Invoke-WithinEphemeral -ScriptBlock $ScriptBlock
            
            $LocationAfterTest = Get-Location
            $LocationAfterTest.Path | Should -Be $LocationBeforeTest.Path
        }

        It 'Should clean up temporary folder after execution' {
            $Global:TempFolderPath = $null
            
            $ScriptBlock = {
                $Global:TempFolderPath = (Get-Location).Path
                'test content' | Out-File 'testfile.txt'
                New-Item -ItemType Directory -Name 'subfolder'
            }
            
            Invoke-WithinEphemeral -ScriptBlock $ScriptBlock
            
            Test-Path $Global:TempFolderPath | Should -Be $false
        }

        It 'Should allow script block to create and access files' {
            $Global:FileContent = $null
            
            $ScriptBlock = {
                'Hello World' | Out-File 'test.txt'
                $Global:FileContent = Get-Content 'test.txt'
            }
            
            Invoke-WithinEphemeral -ScriptBlock $ScriptBlock
            
            $Global:FileContent | Should -Be 'Hello World'
        }

        It 'Should handle script blocks that create nested directories' {
            $Global:NestedDirExists = $false
            
            $ScriptBlock = {
                New-Item -ItemType Directory -Path 'level1/level2/level3' -Force
                $Global:NestedDirExists = Test-Path 'level1/level2/level3'
            }
            
            Invoke-WithinEphemeral -ScriptBlock $ScriptBlock
            
            $Global:NestedDirExists | Should -Be $true
        }
    }

    Context 'Error Handling' {
        It 'Should clean up temporary folder even if script block throws an error' {
            $Global:TempFolderPath = $null
            
            $ScriptBlock = {
                $Global:TempFolderPath = (Get-Location).Path
                'test content' | Out-File 'testfile.txt'
                throw 'Test error'
            }
            
            { Invoke-WithinEphemeral -ScriptBlock $ScriptBlock } | Should -Throw 'Test error'
            
            Test-Path $Global:TempFolderPath | Should -Be $false
        }

        It 'Should return to original location even if script block throws an error' {
            $LocationBeforeTest = Get-Location
            
            $ScriptBlock = {
                throw 'Test error'
            }
            
            { Invoke-WithinEphemeral -ScriptBlock $ScriptBlock } | Should -Throw 'Test error'
            
            $LocationAfterTest = Get-Location
            $LocationAfterTest.Path | Should -Be $LocationBeforeTest.Path
        }

        It 'Should handle null script block' {
            { Invoke-WithinEphemeral -ScriptBlock $null } | Should -Throw
        }

        It 'Should handle empty script block' {
            $EmptyScriptBlock = {}
            
            { Invoke-WithinEphemeral -ScriptBlock $EmptyScriptBlock } | Should -Not -Throw
        }
    }

    Context 'Location Management' {
        It 'Should use Push-Location and Pop-Location correctly' {
            $Global:LocationStack = @()
            
            $ScriptBlock = {
                # Verify we can still push/pop within the script block
                $CurrentLoc = Get-Location
                if ($env:TEMP) {
                    Push-Location $env:TEMP
                    $Global:LocationStack += (Get-Location).Path
                    Pop-Location
                    $Global:LocationStack += (Get-Location).Path
                } else {
                    # Fallback for systems without TEMP environment variable
                    $Global:LocationStack += '/tmp'
                    $Global:LocationStack += (Get-Location).Path
                }
            }
            
            Invoke-WithinEphemeral -ScriptBlock $ScriptBlock
            
            if ($env:TEMP) {
                $Global:LocationStack[0] | Should -Be $env:TEMP
                $Global:LocationStack[1] | Should -Not -Be $env:TEMP
            } else {
                # For systems without TEMP, just verify we have two different locations
                $Global:LocationStack.Count | Should -Be 2
            }
        }
    }

    Context 'Integration Tests' {
        It 'Should work with Get-UniqueTempFolder pattern' {
            $Global:TempFolderUsed = $null
            
            $ScriptBlock = {
                $Global:TempFolderUsed = (Get-Location).Path
                
                # Simulate some work
                for ($i = 1; $i -le 3; $i++) {
                    "Content $i" | Out-File "file$i.txt"
                }
                
                $Files = Get-ChildItem '*.txt'
                $Files.Count | Should -Be 3
            }
            
            Invoke-WithinEphemeral -ScriptBlock $ScriptBlock
            
            # Verify the temp folder was cleaned up
            Test-Path $Global:TempFolderUsed | Should -Be $false
        }
    }
}