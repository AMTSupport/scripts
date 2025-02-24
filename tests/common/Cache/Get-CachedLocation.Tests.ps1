BeforeDiscovery { Import-Module -Force -Name $PSScriptRoot/../../../src/common/Cache.psm1 }
AfterAll { Remove-Module -Name Cache }

Describe 'Get-CachedLocation Tests' {
    BeforeAll { Set-Variable -Name CacheName -Value "UNIQUE_CACHE_NAME" }

    It "Creates the cache folder if missing" {
        Mock Test-Path {
            return $false
        } -ParameterFilter { $Path -eq "$($Script:Folder)" }

        Mock New-Item {}
        Mock Remove-Item {}
        Mock Set-Content {}

        $Result = Get-CachedLocation -Name "test" -CreateBlock { return @{ Data = "Test" } }

        Should -Invoke Test-Path -Exactly -Times 1
        Should -Invoke New-Item -Exactly -Times 1
        $Result | Should -Match "Cached-test"
    }

    It "Removes the cache if -NoCache is specified" {
        Mock Test-Path { return $true }
        Mock Remove-Item {}
        Mock Set-Content {}

        Get-CachedLocation -Name "test" -NoCache -CreateBlock { return @{ Data = "Test" } } | Out-Null
        Should -Invoke Remove-Item -Exactly -Times 1
    }

    It "Uses CreateBlock if cache file does not exist" {
        Mock Test-Path { return $false }
        Mock Set-Content {}

        $Result = Get-CachedLocation -Name "test" -CreateBlock { return @{ Data = "Created" } }
        Should -Invoke Set-Content -Exactly -Times 1
        $Result | Should -Match "Cached-test"
    }

    Context 'Cache folder handling' {
        It 'Creates the cache folder when missing' {
            Mock Test-Path {
                # Folder not present for first check
                if ($Path -eq "$($Script:Folder)") { return $false }
                # Cache file does not exist for subsequent checks
                return $false
            }
            Mock New-Item {}
            Mock Set-Content {}
            Mock Remove-Item {}

            $Result = Get-CachedLocation -Name 'test' -CreateBlock { return '{"data":"new"}' }
            Should -Invoke New-Item -Exactly -Times 1
            $Result | Should -Match 'Cached-test'
        }

        It 'Does not recreate folder if it already exists' {
            Mock Test-Path { return $true }
            Mock New-Item {}
            Mock Set-Content {}

            $Result = Get-CachedLocation -Name 'test2' -CreateBlock { return '{"data":"xyz"}' }
            Should -Invoke New-Item -Times 0
            $Result | Should -Match 'Cached-test2'
        }
    }

    Context 'Cache file checks' {
        It 'Removes existing file if -NoCache is used' {
            Mock Test-Path { return $true }
            Mock Remove-Item {}
            Mock Set-Content {}

            Get-CachedLocation -Name 'test' -NoCache -CreateBlock { return '{"data":"fresh"}' } | Out-Null
            Should -Invoke Remove-Item -Times 1
        }

        It 'Removes cache if MaxAge is exceeded' {
            Mock Test-Path { return $true }
            Mock (Get-Item) {
                # Return a last-write time older than 1 day
                return [PSCustomObject]@{ LastWriteTime = (Get-Date).AddDays(-2) }
            }
            Mock Remove-Item {}
            Mock Set-Content {}

            Get-CachedLocation -Name 'test' -MaxAge ([TimeSpan]::FromHours(12)) -CreateBlock { return '{"test":"maxage"}' } | Out-Null
            Should -Invoke Remove-Item -Times 1
        }

        It 'Uses IsValidBlock to remove invalid cache' {
            Mock Test-Path { return $true }
            Mock Remove-Item {}
            Mock Set-Content {}
            Mock (Get-Item) {
                return [PSCustomObject]@{ LastWriteTime = (Get-Date) }
            }

            $validBlock = { param($path) return $false }
            Get-CachedLocation -Name 'test' -IsValidBlock $validBlock -CreateBlock { return '{"invalid":"cache"}' } | Out-Null
            Should -Invoke Remove-Item -Times 1
        }

        It 'Creates a new file when none is found' {
            Mock Test-Path {
                # Folder exists, cache file doesn't
                if ($_ -eq "$($Script:Folder)") { return $true }
                return $false
            }
            Mock Set-Content {}

            $Result = Get-CachedLocation -Name 'brandNew' -CreateBlock { return '{"created":"newfile"}' }
            Should -Invoke Set-Content -Times 1
            $Result | Should -Match 'Cached-brandNew'
        }
    }
}
