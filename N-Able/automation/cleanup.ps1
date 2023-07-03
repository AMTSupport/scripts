#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.DESCRIPTION

.NOTES
    If the user has an explorer instance open we can't delete the thumbnails or iconcache files, Need to find a way to schedule this to run when explorer is not running if possible.
    There is one more location which windows stores DirextX shader cache files but I can't find it.
#>

# Section start :: Custom Classes

enum Ageable {
    FromCreation;
    FromLastWrite;
    Never;
}

Class File {
    [System.IO.FileInfo]$FileInfo;
    [Boolean]$NotifyOnly;

    File([System.IO.FileInfo]$FileInfoIn, [Boolean]$NotifyOnlyIn) {
        $this.FileInfo = $FileInfoIn
        $this.NotifyOnly = $NotifyOnlyIn
    }
}

Class Parent {
    [String] $Path;

    Parent([String]$PathIn) {
        $this.Path = $PathIn
    }

    [String] parse([String]$PartialPath) {
        return [System.IO.Path]::Combine($this.Path, $PartialPath)
    }
}

Class ChildResult {
    [File[]] $Files;
    [System.IO.DirectoryInfo[]] $Directories;

    ChildResult([File[]]$FilesIn, [System.IO.DirectoryInfo[]]$DirectoriesIn) {
        $this.Files = $FilesIn
        $this.Directories = $DirectoriesIn
    }

    Combined([ChildResult]$ChildResultIn) {
        $this.Files += $ChildResultIn.Files
        $this.Directories += $ChildResultIn.Directories
    }
}

Class Cleanable {
    [String] $PartialPath;
    [Int16] $MaxAge;
    [Ageable] $Ageable;
    [Boolean] $NotifyOnly;

    Cleanable([String]$PathIn) {
        $this.PartialPath = $PathIn
        $this.MaxAge = -1
        $this.Ageable = [Ageable]::Never
        $this.NotifyOnly = $false
    }

    Cleanable([String]$PathIn, [Boolean]$NotifyOnlyIn) {
        $this.PartialPath = $PathIn
        $this.MaxAge = -1
        $this.Ageable = [Ageable]::Never
        $this.NotifyOnly = $NotifyOnlyIn
    }

    Cleanable([String]$PathIn, [Int16]$MaxAgeIn, [Ageable]$AgeableIn) {
        $this.PartialPath = $PathIn
        $this.MaxAge = $MaxAgeIn
        $this.Ageable = $AgeableIn
        $this.NotifyOnly = $false
    }

    Cleanable([String]$PathIn, [Int16]$MaxAgeIn, [Ageable]$AgeableIn, [Boolean]$NotifyOnlyIn) {
        $this.PartialPath = $PathIn
        $this.MaxAge = $MaxAgeIn
        $this.Ageable = $AgeableIn
        $this.NotifyOnly = $NotifyOnlyIn
    }

    [ChildResult] GetChildren([Parent[]]$Parents) {
        [String[]]$paths = $Parents | ForEach-Object { $_.parse($this.PartialPath) }
        
        Log-Verbose "Getting children for: $($paths -join ', ')"

        [System.IO.FileSystemInfo[]]$children = $paths | ForEach-Object { Get-ChildItem -Path $_ -Force -Recurse } | ForEach-Object { $_ }
        [File[]]$filteredChildren = @()
        [System.IO.DirectoryInfo[]]$filteredDirectories = @()

        foreach ($child in $children) {
            # Separate directories so we can clean them after if they're empty.
            if ($child -is [System.IO.DirectoryInfo]) {
                $filteredDirectories += $child
                continue
            }

            # Skip files that are in use.
            if (Test-FileLock $child.FullName) {
                Log-Verbose "File is locked: $($child.FullName)"
                continue
            }

            # Skip files that we can't access.
            # if (Test-AccessDenied $child.FullName) {
            #     Write-Host "Access denied for: $($child.FullName)"
            #     continue
            # }

            # Skip files that are too new.
            if ($this.MaxAge -ge 1 -and $this.Ageable -ne [Ageable]::Never) {
                if ($this.Ageable -eq [Ageable]::FromCreation) {
                    $age = (Get-Date) - $child.CreationTime
                } else {
                    $age = (Get-Date) - $child.LastWriteTime
                }

                if ($age.Days -le $this.MaxAge) {
                    Log-Verbose "File is too new: $($child.FullName)"
                    continue
                }
            }

            $filteredChildren += [File]::new($child, $this.NotifyOnly)
        }

        return [ChildResult]::new($filteredChildren, $filteredDirectories)
    }
}

# Section end :: Custom Classes

# Section start :: Set Variables

# Locations which are checked on each installed drive.
[Cleanable[]]$driveLocations = @(
    [Cleanable]::new("`$Recycle.Bin", 7, [Ageable]::FromLastWrite)                   # Delete files in the recycle bin older than 7 days.
)

# Locations which are checked only on the system drive.
# TODO :: Add AMD Driver locations
[Cleanable[]]$rootLocations = @(
    [Cleanable]::new("Temp"),                                       # Cleanup system temp files.
    [Cleanable]::new("ProgramData\NVIDIA"),                         # Cleanup NVIDIA Logs.
    [Cleanable]::new("ProgramData\NVIDIA Corporation\Downloader"),  # Cleanup NVIDIA Driver downloads.
    [Cleanable]::new("NinitePro\NiniteDownloads\Files"),            # Cleanup NinitePro downloads.
    [Cleanable]::new("ProgramData\Microsoft\Windows\WER\ReportArchive")
)

# The windir locations typically located at `C:\Windows`.
[Cleanable[]]$windirLocations = @(
    [Cleanable]::new("Downloaded Program Files"),                   # Cleanup ActiveX Installers.
    [Cleanable]::new("SoftwareDistribution\Download", $true),       # Cleanup Windows Update downloads.
    [Cleanable]::new("Prefetch"),                                   # Cleanup Prefetch files.
    [Cleanable]::new("Temp"),                                       # Cleanup Windows temp files.
    [Cleanable]::new("Panther", 14, [Ageable]::FromLastWrite),      # Cleanup Windows Setup logs.
    [Cleanable]::new("Minidump", 7, [Ageable]::FromCreation)        # Cleanup Windows Minidump files.
)

# The locations to search with the users directory.
[Cleanable[]]$userLocations = @(
    [Cleanable]::new("AppData\Local\Temp"),                                               # Cleanup user temp files.
    [Cleanable]::new("AppData\Local\Microsoft\Windows\Explorer\thumbcache_*"),            # Thumbnail Cache
    [Cleanable]::new("AppData\Local\Microsoft\Windows\Explorer\iconcache_*"),             # Icon Cache
    [Cleanable]::new("AppData\Local\NVIDIA\DXCache"),                                     # NVIDIA Shader Cache
    [Cleanable]::new("AppData\Local\D3DSCache"),                                          # DirectX Shader Cache
    [Cleanable]::new("AppData\Local\Microsoft\Windows\INetCache\IE"),                     # IE/Edge Cache
    [Cleanable]::new("AppData\Local\Microsoft\Edge\User Data\Default\Cache"),             # Edge Cache
    [Cleanable]::new("AppData\Local\Google\Chrome\User Data\Default\Cache"),              # Chrome Cache
    [Cleanable]::new("AppData\Local\Mozilla\Firefox\Profiles\*.default-release\cache2")   # Firefox Cache
)

# Section end :: Set variables

# Section start :: Utility functions

function Write-Log() {
    process {
        if (-not (Test-Path "$($env:TEMP)\AMT")) {
            New-Item -Path "$($env:TEMP)\AMT" -ItemType Directory | Out-Null
        }

        if (-not (Test-Path "$($env:TEMP)\AMT\Cleaner.log")) {
            New-Item -Path "$($env:TEMP)\AMT\Cleaner.log" -ItemType File | Out-Null
        }

        $global:fileLogs | Out-File -FilePath "$($env:TEMP)\AMT\Cleaner.log" -Append
    }
}

function Append-Log ([String]$Message) {
    process {
        $global:fileLogs += ("[{0}|{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Type,$Message)
    }
}

function Log-Info ([String]$Message) {
    process {
        Write-Host "[INFO] $Message"
        Append-Log $Message
    }
}

function Log-Error ([String]$Message) {
    process {
        Write-Host "[ERROR] $Message"
        Append-Log $Message
    }
}

function Log-Verbose ([String]$Message) {
    process {
        if ($global:Verbose -eq $true) {
            Write-Host "[VERBOSE] $Message"
        }

        Append-Log $Message
    }
}

# Improvised from https://stackoverflow.com/a/24992975
function Test-FileLock ([Parameter(Mandatory = $true)] [String]$Path) {
    $oFile = [System.IO.FileInfo]::new($Path)
  
    if ((Test-Path -Path $Path) -eq $false) {
        return $false
    }
  
    try {
        $oStream = $oFile.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
  
        if ($oStream) {
            $oStream.Close()
        }

    } catch [System.UnauthorizedAccessException], [System.IO.IOException] {
        if ($_.Exception -is [System.IO.IOException]) { return $true }
    }

    return $false
  }

# Should be a better way around this.
function Test-AccessDenied ([Parameter(ValueFromPipeline)] [String]$Path) {
    process {
        $oFile = [System.IO.FileInfo]::new($Path)
  
        if ((Test-Path -Path $Path) -eq $false) {
            return $false
        }
      
        try {
            $oStream = $oFile.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
      
            if ($oStream) {
                $oStream.Close()
            }
        } catch [System.UnauthorizedAccessException], [System.IO.IOException] {
            if ($_.Exception -is [System.UnauthorizedAccessException]) { return $true }
        }

        return $false
    }
}

function Parse-Arguments ([Parameter()] [String[]]$Arguments) {
    process {
        if ($Arguments.Count -eq 0) {
            return
        }

        if ($Arguments -contains "-d" -or $Arguments -contains "--dry") {
            Log-Info "Dry run enabled. No changes will be made."
            $global:DryRun = $true
            return
        }

        if ($Arguments -contains "-v" -or $Arguments -contains "--verbose") {
            Log-Verbose "Verbose mode enabled. Additional information will be displayed."
            $global:Verbose = $true
            return
        }

        $global:DryRun = $false
        $global:Verbose = $false
    }
}

# Section end :: Utility functions

# Section start :: Action functions

function Init {
    process {
        Log-Info "Starting Cleanup Job."

        $global:DryRun = $null
        $global:Verbose = $null
        $global:fileLogs = @()

        $Error.Clear()
    }
}

function Parse-Locations {
    process {
        Log-Info "Parsing Locations."

        $cleanable = $driveLocations.GetChildren((Get-PSDrive -PSProvider FileSystem | ForEach-Object { [Parent]::new("$($_.Name):\") }))
        $cleanableRoot = $rootLocations.GetChildren([Parent]::new("$($env:SystemDrive)\"))
        $cleanableWinDr = $windirLocations.GetChildren([Parent]::new($env:windir))
        $cleanableUser = $userLocations.GetChildren((Get-ChildItem -Path "$($env:SystemDrive)\Users" -Directory | ForEach-Object { [Parent]::new($_.FullName) }))

        [File[]]$files = ($cleanable.Files + $cleanableRoot.Files + $cleanableWinDr.Files + $cleanableUser.Files)
        [System.IO.DirectoryInfo[]]$directories = ($cleanable.Directories + $cleanableRoot.Directories + $cleanableWinDr.Directories + $cleanableUser.Directories)

        return [ChildResult]::new($files, $directories)
    }
}

function Clean ([Parameter(Mandatory = $true)] [ChildResult]$result) {
    process {
        Log-Info "Cleaning Locations. Dry Run: $global:DryRun"

        if ($result.Files.Count -gt 0) {
            $removeableFiles = @()
            $notifyOnlyFiles = @()
    
            foreach ($file in $result.Files) {
                if ($file.NotifyOnly -eq $true) {
                    $notifyOnlyFiles += $file
                    continue
                }
    
                $removeableFiles += $file
            }

            Log-Verbose "Files being removed: $(($removeableFiles | ForEach-Object { $_.FileInfo.FullName }) -Join "`r`n")"
            Log-Info "Removing $($removeableFiles.Count) files. Total Size: $(($removeableFiles | ForEach-Object { $_.FileInfo } | Measure-Object -Property Length -Sum).Sum / 1MB)MB"
    
            if ($global:DryRun -ne $true -and $removeableFiles.Count -gt 0) {
                $removeableFiles | ForEach-Object {
                    if ($_ -eq $null) { continue }
                    Log-Verbose "Deleting: $($_.FileInfo.FullName)"
                    Remove-Item -Path $_.FileInfo.FullName -Force # TODO :: Check access rights in filter so we don't need to silently continue.
                }
            }
        }

        if ($result.Directories.Count -gt 0 -and $global:DryRun -ne $true) {
            Log-Info "Removing Empty Directories."
            $result.Directories | ForEach-Object {
                if ((Get-ChildItem -Path $_.FullName -Force).Count -gt 0) {
                    Log-Verbose "Skipping non-empty Directory: $($_)"
                    continue
                }

                Log-Verbose "Deleting empty Directory: $($_)"
                Remove-Item -Path $_.FullName -ErrorAction SilentlyContinue # TODO :: Check access rights in filter so we don't need to silently continue.
            }
        }

        if ($notifyOnlyFiles.Count -gt 0) {
            Log-Verbose "Additional Files for manual review (NotifyOnly): $(($notifyOnlyFiles | ForEach-Object { $_.FileInfo.FullName }) -Join "`r`n")"
            Log-Info "Possible Free Space of files marked for Notify Only: $(($notifyOnlyFiles | ForEach-Object { $_.FileInfo } | Measure-Object -Property Length -Sum).Sum / 1MB)MB"
        }
    }
}

function Finalise {
    process {
        Log-Info "Finished Cleanup Job."

        Write-Log

        $global:DryRun = $null
        $global:Verbose = $null
        $global:fileLogs = $null

        $Error.Clear()
    }
}

# Section end :: Action Functions

# Section start :: Function Invoking

Init
Parse-Arguments -Arguments $args
Clean -result (Parse-Locations)
Finalise

# Section end :: Function Invoking
