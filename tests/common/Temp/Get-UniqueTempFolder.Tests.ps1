BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/Temp.psm1" }

Describe 'Get-UniqueTempFolder Tests' {
    BeforeAll {
        $TestTempPath = [System.IO.Path]::GetTempPath()
    }

    AfterEach {
        # Clean up any test folders created
        Get-ChildItem -Path $TestTempPath -Directory | Where-Object { $_.CreationTime -gt (Get-Date).AddMinutes(-1) } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'Basic Functionality' {
        It 'Should create a unique folder in temp directory' {
            $Result = Get-UniqueTempFolder
            
            $Result | Should -Not -BeNullOrEmpty
            Test-Path $Result -PathType Container | Should -Be $true
            $Result | Should -BeLike "$TestTempPath*"
        }

        It 'Should create different folders on multiple calls' {
            $Folder1 = Get-UniqueTempFolder
            $Folder2 = Get-UniqueTempFolder
            
            $Folder1 | Should -Not -Be $Folder2
            Test-Path $Folder1 -PathType Container | Should -Be $true
            Test-Path $Folder2 -PathType Container | Should -Be $true
        }

        It 'Should create empty folders' {
            $Result = Get-UniqueTempFolder
            
            $ChildItems = Get-ChildItem -Path $Result
            $ChildItems | Should -BeNullOrEmpty
        }

        It 'Should use random file names' {
            $Folder1 = Get-UniqueTempFolder
            $Folder2 = Get-UniqueTempFolder
            $Folder3 = Get-UniqueTempFolder
            
            $Name1 = Split-Path $Folder1 -Leaf
            $Name2 = Split-Path $Folder2 -Leaf
            $Name3 = Split-Path $Folder3 -Leaf
            
            $Name1 | Should -Not -Be $Name2
            $Name2 | Should -Not -Be $Name3
            $Name1 | Should -Not -Be $Name3
        }
    }

    Context 'Integration with Get-NamedTempFolder' {
        It 'Should use Get-NamedTempFolder internally with ForceEmpty' {
            # Create a folder with the same name that would be generated
            $RandomName = [System.IO.Path]::GetRandomFileName()
            
            # Mock Get-NamedTempFolder to verify it's called with ForceEmpty
            Mock Get-NamedTempFolder -ModuleName Temp -MockWith {
                param($Name, $ForceEmpty)
                $ForceEmpty | Should -Be $true
                Join-Path $TestTempPath $Name
            }
            
            $Result = Get-UniqueTempFolder
            
            Assert-MockCalled Get-NamedTempFolder -ModuleName Temp -Exactly 1
        }
    }
}