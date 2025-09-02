BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/Temp.psm1" }

Describe 'Get-NamedTempFolder Tests' {
    BeforeAll {
        $TestTempPath = [System.IO.Path]::GetTempPath()
    }

    AfterEach {
        # Clean up any test folders created
        Get-ChildItem -Path $TestTempPath -Directory | Where-Object { $_.Name -like 'PesterTest*' } | Remove-Item -Recurse -Force
    }

    Context 'Basic Functionality' {
        It 'Should create a new folder with the specified name' {
            $FolderName = 'PesterTestFolder'
            $Result = Get-NamedTempFolder -Name $FolderName
            
            $Result | Should -Be (Join-Path $TestTempPath $FolderName)
            Test-Path $Result -PathType Container | Should -Be $true
        }

        It 'Should return existing folder if it already exists' {
            $FolderName = 'PesterTestExisting'
            $ExpectedPath = Join-Path $TestTempPath $FolderName
            
            # Create the folder first
            New-Item -ItemType Directory -Path $ExpectedPath -Force | Out-Null
            
            $Result = Get-NamedTempFolder -Name $FolderName
            
            $Result | Should -Be $ExpectedPath
            Test-Path $Result -PathType Container | Should -Be $true
        }

        It 'Should handle folder names with special characters' {
            $FolderName = 'PesterTest-Folder_123'
            $Result = Get-NamedTempFolder -Name $FolderName
            
            $Result | Should -Be (Join-Path $TestTempPath $FolderName)
            Test-Path $Result -PathType Container | Should -Be $true
        }
    }

    Context 'ForceEmpty Parameter' {
        It 'Should empty existing folder when ForceEmpty is specified' {
            $FolderName = 'PesterTestForceEmpty'
            $FolderPath = Join-Path $TestTempPath $FolderName
            
            # Create folder with some content
            New-Item -ItemType Directory -Path $FolderPath -Force | Out-Null
            $TestFile = Join-Path $FolderPath 'testfile.txt'
            'test content' | Out-File -FilePath $TestFile
            
            # Verify file exists
            Test-Path $TestFile | Should -Be $true
            
            $Result = Get-NamedTempFolder -Name $FolderName -ForceEmpty
            
            $Result | Should -Be $FolderPath
            Test-Path $Result -PathType Container | Should -Be $true
            Test-Path $TestFile | Should -Be $false
        }

        It 'Should create folder if it does not exist when ForceEmpty is specified' {
            $FolderName = 'PesterTestForceEmptyNew'
            $ExpectedPath = Join-Path $TestTempPath $FolderName
            
            Test-Path $ExpectedPath | Should -Be $false
            
            $Result = Get-NamedTempFolder -Name $FolderName -ForceEmpty
            
            $Result | Should -Be $ExpectedPath
            Test-Path $Result -PathType Container | Should -Be $true
        }

        It 'Should handle nested folders when ForceEmpty is specified' {
            $FolderName = 'PesterTestNested'
            $FolderPath = Join-Path $TestTempPath $FolderName
            
            # Create folder with nested structure
            New-Item -ItemType Directory -Path $FolderPath -Force | Out-Null
            $NestedFolder = Join-Path $FolderPath 'nested'
            New-Item -ItemType Directory -Path $NestedFolder -Force | Out-Null
            $TestFile = Join-Path $NestedFolder 'testfile.txt'
            'test content' | Out-File -FilePath $TestFile
            
            $Result = Get-NamedTempFolder -Name $FolderName -ForceEmpty
            
            $Result | Should -Be $FolderPath
            Test-Path $Result -PathType Container | Should -Be $true
            Test-Path $NestedFolder | Should -Be $false
            Test-Path $TestFile | Should -Be $false
        }
    }

    Context 'Error Handling' {
        It 'Should handle empty folder name' {
            { Get-NamedTempFolder -Name '' } | Should -Throw
        }

        It 'Should handle null folder name' {
            { Get-NamedTempFolder -Name $null } | Should -Throw
        }

        It 'Should handle folder names with trailing whitespace' {
            # Trailing whitespace gets trimmed by the filesystem
            $FolderName = 'PesterTestWhitespace   '
            $Result = Get-NamedTempFolder -Name $FolderName
            
            # The result should be the expected path, but filesystem trims trailing space
            $Result | Should -Be (Join-Path $TestTempPath $FolderName)
            # The folder should exist (filesystem trims the trailing spaces)
            Test-Path (Join-Path $TestTempPath 'PesterTestWhitespace') -PathType Container | Should -Be $true
        }
    }
}