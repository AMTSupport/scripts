BeforeDiscovery { Import-Module "$PSScriptRoot/../../../src/common/Cache.psm1" }
AfterAll { Remove-Module -Name Cache }

Describe 'Get-CachedContent Tests' {
    BeforeAll {
        InModuleScope Cache {
            $Script:Folder = "TestDrive:\PSCache"
        }

        $CreateBlock = { return '{"NewCache":"Content"}' }
    }

    AfterEach { InModuleScope Cache {
        Remove-Item -Path $Script:Folder -Recurse -Force
    }}

    Context 'Get-CachedContent' {
        It 'Creates cache file if it does not exist' {
            $Result = Get-CachedContent -Name 'test' -CreateBlock $CreateBlock;
            $Result.NewCache | Should -Be 'Content';
        }

        It 'Returns cached content if it exists' {
            $Result = Get-CachedContent -Name 'test' -CreateBlock { return '{"NewCache":"OldContent"}' };
            $Result = Get-CachedContent -Name 'test' -CreateBlock $CreateBlock;
            $Result.NewCache | Should -Be 'OldContent';
        }
    }
}
