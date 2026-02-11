BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/Temp.psm1" }

Describe 'Get-UniqueTempFolder Tests' {
    Context 'Basic Functionality' {
        It 'Should create a unique folder in temp directory' {
            $Result = Get-UniqueTempFolder

            $Result | Should -Not -BeNullOrEmpty
            Test-Path $Result -PathType Container | Should -Be $true
            $Result | Should -BeLike "$([System.IO.Path]::GetTempPath())*"
        }

        It 'Should create different folders on multiple calls' {
            $Folder1 = Get-UniqueTempFolder
            $Folder2 = Get-UniqueTempFolder

            $Folder1 | Should -Not -Be $Folder2
        }

        It 'Should create empty folders' {
            $Result = Get-UniqueTempFolder

            $ChildItems = Get-ChildItem -Path $Result
            $ChildItems | Should -BeNullOrEmpty
        }
    }
}
