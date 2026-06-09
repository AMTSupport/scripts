#Requires -Version 5.1

BeforeDiscovery {
    Import-Module -Name "$PSScriptRoot/../../../src/common/Lock.psm1" -Force -Scope Global;
}

Describe 'Driver Lock Functions' {
    BeforeAll {
        Import-Module -Name "$PSScriptRoot/../../../src/common/Lock.psm1" -Force -Scope Global;
    }

    Context 'Get-LockPath' {
        It 'Should return path in system temp directory' {
            $Path = Get-LockPath -ScriptName 'SetupPrinter' -ResourceId 'TestVendor';
            $Dir = [System.IO.Path]::GetDirectoryName($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar);
            $Temp = [System.IO.Path]::GetTempPath().TrimEnd([System.IO.Path]::DirectorySeparatorChar);
            $Dir | Should -Be $Temp;
        }

        It 'Should sanitize resource name (remove non-alphanumeric)' {
            $Path = Get-LockPath -ScriptName 'SetupPrinter' -ResourceId 'Konica Minolta';
            $Path | Should -Match 'AMT_SetupPrinter_KonicaMinolta\.lock$';
        }

        It 'Should include resource name in filename' {
            $Path = Get-LockPath -ScriptName 'SetupPrinter' -ResourceId 'HP';
            $Path | Should -Match 'AMT_SetupPrinter_HP\.lock$';
        }

        It 'Should end with .lock extension' {
            $Path = Get-LockPath -ScriptName 'SetupPrinter' -ResourceId 'Ricoh';
            [System.IO.Path]::GetExtension($Path) | Should -Be '.lock';
        }

        It 'Should strip all non-alphanumeric characters from resource name' {
            $Path = Get-LockPath -ScriptName 'SetupPrinter' -ResourceId 'H.P. (Test)!@#';
            $Path | Should -Match 'AMT_SetupPrinter_HPTest\.lock$';
        }

        It 'Should handle empty-ish resource name' {
            $Path = Get-LockPath -ScriptName 'SetupPrinter' -ResourceId '!!!';
            $Path | Should -Match 'AMT_SetupPrinter_\.lock$';
        }

        It 'Should derive script name from stack when not specified' {
            $Path = Get-LockPath -ResourceId 'Ricoh';
            $Path | Should -Match 'AMT_.+_Ricoh\.lock$';
            $Path | Should -Not -BeNullOrEmpty;
        }
    }

    Context 'Wait-LockFile' {
        AfterEach {
            if ($Script:LockHandle) {
                try { $Script:LockHandle.Close() } catch { }
                $Script:LockHandle = $null;
            }
            if ($Script:LockPath -and (Test-Path -Path $Script:LockPath)) {
                Remove-Item -Path $Script:LockPath -Force -ErrorAction SilentlyContinue;
            }
        }

        It 'Should create lock file if not exists' {
            $Script:LockPath = Join-Path ([System.IO.Path]::GetTempPath()) "AMT_TestLock_$([Guid]::NewGuid().ToString('N')).lock";
            $Script:LockHandle = Wait-LockFile -LockPath $Script:LockPath -LockOwner 'Test';
            Test-Path -Path $Script:LockPath | Should -Be $true;
        }

        It 'Should return file handle with exclusive access' {
            $Script:LockPath = Join-Path ([System.IO.Path]::GetTempPath()) "AMT_TestLock_$([Guid]::NewGuid().ToString('N')).lock";
            $Script:LockHandle = Wait-LockFile -LockPath $Script:LockPath -LockOwner 'Test';
            $Script:LockHandle | Should -Not -BeNullOrEmpty;
            $Script:LockHandle.CanWrite | Should -Be $true;
            $Script:LockHandle.CanRead | Should -Be $true;
        }

        It 'Should write PID to lock file' {
            $Script:LockPath = Join-Path ([System.IO.Path]::GetTempPath()) "AMT_TestLock_$([Guid]::NewGuid().ToString('N')).lock";
            $Handle = Wait-LockFile -LockPath $Script:LockPath -LockOwner 'Ricoh';

            # Read content through the open handle via seek/read to avoid exclusive-lock conflict
            $Handle.Position = 0;
            $Reader = [System.IO.StreamReader]::new($Handle);
            $Content = $Reader.ReadToEnd();
            $Reader.Close();

            $Content | Should -Match "PID=$PID";

            $Handle.Close();
            $Script:LockHandle = $null;
        }

        It 'Should write Owner to lock file when specified' {
            $Script:LockPath = Join-Path ([System.IO.Path]::GetTempPath()) "AMT_TestLock_$([Guid]::NewGuid().ToString('N')).lock";
            $Handle = Wait-LockFile -LockPath $Script:LockPath -LockOwner 'Ricoh';

            $Handle.Position = 0;
            $Reader = [System.IO.StreamReader]::new($Handle);
            $Content = $Reader.ReadToEnd();
            $Reader.Close();

            $Content | Should -Match 'Owner=Ricoh';

            $Handle.Close();
            $Script:LockHandle = $null;
        }

        It 'Should write Started timestamp to lock file' {
            $Script:LockPath = Join-Path ([System.IO.Path]::GetTempPath()) "AMT_TestLock_$([Guid]::NewGuid().ToString('N')).lock";
            $Handle = Wait-LockFile -LockPath $Script:LockPath -LockOwner 'Test';

            $Handle.Position = 0;
            $Reader = [System.IO.StreamReader]::new($Handle);
            $Content = $Reader.ReadToEnd();
            $Reader.Close();

            $Content | Should -Match 'Started=\d{4}-\d{2}-\d{2}T';

            $Handle.Close();
            $Script:LockHandle = $null;
        }

        It 'Should omit Owner line when no owner specified' {
            $Script:LockPath = Join-Path ([System.IO.Path]::GetTempPath()) "AMT_TestLock_$([Guid]::NewGuid().ToString('N')).lock";
            $Handle = Wait-LockFile -LockPath $Script:LockPath;

            $Handle.Position = 0;
            $Reader = [System.IO.StreamReader]::new($Handle);
            $Content = $Reader.ReadToEnd();
            $Reader.Close();

            $Content | Should -Not -Match 'Owner=';
            $Content | Should -Match "PID=$PID";
            $Content | Should -Match 'Started=';

            $Handle.Close();
            $Script:LockHandle = $null;
        }

        It 'Should create lock directory if missing' {
            $Script:LockPath = Join-Path ([System.IO.Path]::GetTempPath()) "AMT_SubDir_$([Guid]::NewGuid().ToString('N'))\lock.lock";
            $Script:LockHandle = Wait-LockFile -LockPath $Script:LockPath -LockOwner 'Test';
            Test-Path -Path (Split-Path -Path $Script:LockPath -Parent) | Should -Be $true;
            Test-Path -Path $Script:LockPath | Should -Be $true;
        }
    }

    Context 'Release-LockFile' {
        AfterEach {
            if ($Script:LockHandle) {
                try { $Script:LockHandle.Close() } catch { }
            }
            if ($Script:LockPath -and (Test-Path -Path $Script:LockPath)) {
                Remove-Item -Path $Script:LockPath -Force -ErrorAction SilentlyContinue;
            }
        }

        It 'Should close handle without error' {
            $Script:LockPath = Join-Path ([System.IO.Path]::GetTempPath()) "AMT_TestLock_$([Guid]::NewGuid().ToString('N')).lock";
            $Script:LockHandle = Wait-LockFile -LockPath $Script:LockPath -LockOwner 'Test';
            { Release-LockFile -LockHandle $Script:LockHandle -LockPath $Script:LockPath } | Should -Not -Throw;
        }

        It 'Should remove lock file if exists' {
            $LockPath = Join-Path ([System.IO.Path]::GetTempPath()) "AMT_TestLock_$([Guid]::NewGuid().ToString('N')).lock";
            $Handle = Wait-LockFile -LockPath $LockPath -LockOwner 'Test';
            Release-LockFile -LockHandle $Handle -LockPath $LockPath;
            Test-Path -Path $LockPath | Should -Be $false;
        }

        It 'Should not error if handle is $null' {
            $LockPath = Join-Path ([System.IO.Path]::GetTempPath()) "AMT_TestLock_$([Guid]::NewGuid().ToString('N')).lock";
            { Release-LockFile -LockHandle $null -LockPath $LockPath } | Should -Not -Throw;
        }

        It 'Should not error if lock file missing' {
            $LockPath = Join-Path ([System.IO.Path]::GetTempPath()) "AMT_TestLock_$([Guid]::NewGuid().ToString('N')).lock";
            $Handle = Wait-LockFile -LockPath $LockPath -LockOwner 'Test';
            Remove-Item -Path $LockPath -Force;
            { Release-LockFile -LockHandle $Handle -LockPath $LockPath } | Should -Not -Throw;
        }

        It 'Should not error if both handle and path are $null' {
            { Release-LockFile -LockHandle $null -LockPath $null } | Should -Not -Throw;
        }

        It 'Should not error if handle is closed but not $null' {
            $LockPath = Join-Path ([System.IO.Path]::GetTempPath()) "AMT_TestLock_$([Guid]::NewGuid().ToString('N')).lock";
            $Handle = Wait-LockFile -LockPath $LockPath -LockOwner 'Test';
            $Handle.Close();
            { Release-LockFile -LockHandle $Handle -LockPath $LockPath } | Should -Not -Throw;
            Test-Path -Path $LockPath | Should -Be $false;
        }
    }

    Context 'Invoke-UnderLock' {
        AfterEach {
            # Determine lock path the same way Invoke-UnderLock does
            $CallerName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.ScriptName);
            $LockPath = Get-LockPath -ScriptName $CallerName -ResourceId $Script:TestManufacturer;
            if (Test-Path -Path $LockPath) {
                Remove-Item -Path $LockPath -Force -ErrorAction SilentlyContinue;
            }
        }

        It 'Should acquire lock before invoking ScriptBlock' {
            $Script:TestManufacturer = 'LockTest' + [Guid]::NewGuid().ToString('N').Substring(0, 8);
            $CallerName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.ScriptName);
            $LockPath = Get-LockPath -ScriptName $CallerName -ResourceId $Script:TestManufacturer;

            Invoke-UnderLock -ResourceId $Script:TestManufacturer -ScriptBlock {
                param($Path)
                Test-Path -Path $Path | Should -Be $true;
            } -ArgumentList $LockPath;

            Test-Path -Path $LockPath | Should -Be $false;
        }

        It 'Should execute ScriptBlock with provided arguments' {
            $Script:TestManufacturer = 'ArgTest' + [Guid]::NewGuid().ToString('N').Substring(0, 8);
            $global:Sum = $null;
            Invoke-UnderLock -ResourceId $Script:TestManufacturer -ScriptBlock {
                param($A, $B) $global:Sum = $A + $B;
            } -ArgumentList 3, 4;
            $global:Sum | Should -Be 7;
        }

        It 'Should execute ScriptBlock without ArgumentList' {
            $Script:TestManufacturer = 'NoArgTest' + [Guid]::NewGuid().ToString('N').Substring(0, 8);
            $global:Executed = $false;
            Invoke-UnderLock -ResourceId $Script:TestManufacturer -ScriptBlock { $global:Executed = $true; };
            $global:Executed | Should -Be $true;
        }

        It 'Should clean up lock even if ScriptBlock throws' {
            $Script:TestManufacturer = 'CleanupTest' + [Guid]::NewGuid().ToString('N').Substring(0, 8);
            $CallerName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.ScriptName);
            $LockPath = Get-LockPath -ScriptName $CallerName -ResourceId $Script:TestManufacturer;

            { Invoke-UnderLock -ResourceId $Script:TestManufacturer -ScriptBlock { throw 'Intentional failure'; } } |
                Should -Throw 'Intentional failure';

            Test-Path -Path $LockPath | Should -Be $false;
        }

        It 'Should re-throw exception after cleanup' {
            $Script:TestManufacturer = 'RethrowTest' + [Guid]::NewGuid().ToString('N').Substring(0, 8);

            { Invoke-UnderLock -ResourceId $Script:TestManufacturer -ScriptBlock { throw 'DownloadError'; } } |
                Should -Throw 'DownloadError';
        }
    }
}
