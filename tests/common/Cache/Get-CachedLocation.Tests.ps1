BeforeDiscovery { Import-Module -Force -Name $PSScriptRoot/../../../src/common/Cache.psm1 }

Describe 'Get-CachedLocation Tests' {
    BeforeAll {
        $CacheName = "UNIQUE_CACHE_NAME";
        InModuleScope Cache {
            $Script:Folder = "$((Get-PSDrive TestDrive).Root)\PSCache"
        }
    }
    AfterEach {
        InModuleScope Cache {
            Remove-Item -Path $Script:Folder -Recurse -Force
        }
    }

    It 'Should return the correct path' {
        InModuleScope Cache -Parameters @{ CacheName = $CacheName } {
            $CachePath = Get-CachedLocation -Name $CacheName -CreateBlock { return "" }
            $CachePath | Should -Be "$Script:Folder\Cached-$CacheName"
        }
    }

    It 'Create the file if it does not exist' {
        InModuleScope Cache -Parameters @{ CacheName = $CacheName; } {
            $Content = [System.Guid]::NewGuid().ToString()
            $CachePath = Get-CachedLocation -Name $CacheName -CreateBlock { return $Content }
            Test-Path -Path $CachePath | Should -Be $true
            Get-Content -Path $CachePath | Should -Be $Content
        }
    }

    It 'Removes existing file if -NoCache is used' {
        InModuleScope Cache -Parameters @{ CacheName = $CacheName; } {
            $Content = [System.Guid]::NewGuid().ToString()
            $CachePath = Get-CachedLocation -Name $CacheName -CreateBlock { return $Content }
            Get-Content -Path $CachePath | Should -Be $Content

            $NewContent = [System.Guid]::NewGuid().ToString()
            Get-CachedLocation -Name $CacheName -CreateBlock { return $NewContent } -NoCache
            Get-Content -Path $CachePath | Should -Be $NewContent
        }
    }

    It 'Should not override existing file' {
        InModuleScope Cache -Parameters @{ CacheName = $CacheName; } {
            $Content = [System.Guid]::NewGuid().ToString()
            $CachePath = Get-CachedLocation -Name $CacheName -CreateBlock { return $Content }
            Get-Content -Path $CachePath | Should -Be $Content

            Get-CachedLocation -Name $CacheName -CreateBlock { return [System.Guid]::NewGuid().ToString() }
            Get-Content -Path $CachePath | Should -Be $Content
        }
    }

    It 'Removes cache if MaxAge is exceeded' {
        InModuleScope Cache -Parameters @{ CacheName = $CacheName; } {
            $Content = [System.Guid]::NewGuid().ToString()
            $CachePath = Get-CachedLocation -Name $CacheName -CreateBlock { return $Content }
            Test-Path -Path $CachePath | Should -Be $true

            Start-Sleep -Seconds 1
            $NewContent = [System.Guid]::NewGuid().ToString()
            $CachePath = Get-CachedLocation -Name $CacheName -CreateBlock { return $NewContent } -MaxAge (New-TimeSpan -Seconds 1)
            Get-Content -Path $CachePath | Should -Be $NewContent
        }
    }

    Context 'IsValidBlock Parameter Tests' {
        It 'Uses IsValidBlock to replace cache' {
            InModuleScope Cache -Parameters @{ CacheName = $CacheName } {
                $InvalidContent = [System.Guid]::NewGuid().ToString()
                $CachePath = Get-CachedLocation -Name $CacheName -CreateBlock { return $InvalidContent }
                Get-Content -Path $CachePath | Should -Be $InvalidContent

                $ValidContent = [System.Guid]::NewGuid().ToString()
                Get-CachedLocation -Name $CacheName -CreateBlock { return $ValidContent } -IsValidBlock { param($Path) return $false }
                Get-Content -Path $CachePath | Should -Be $ValidContent
            }
        }

        It 'Uses IsValidBlock to keep valid cache' {
            InModuleScope Cache -Parameters @{ CacheName = $CacheName } {
                $ValidContent = [System.Guid]::NewGuid().ToString()
                $CachePath = Get-CachedLocation -Name $CacheName -CreateBlock { return $ValidContent }
                Get-Content -Path $CachePath | Should -Be $ValidContent

                $InvalidContent = [System.Guid]::NewGuid().ToString()
                Get-CachedLocation -Name $CacheName -CreateBlock { return $InvalidContent } -IsValidBlock { param($Path) return $true }
                Get-Content -Path $CachePath | Should -Be $ValidContent
            }
        }
    }
}
