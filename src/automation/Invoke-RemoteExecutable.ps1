#Requires -Version 5.1

Param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$ProgramName,

    [Parameter(ValueFromRemainingArguments)]
    [String[]]$Arguments,

    [Parameter(HelpMessage="Don't use the cached response, always call the API.")]
    [Switch]$NoCache
)

function Get-RunnerFolder {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Folder; }

    process {
        [String]$Local:Folder = $Env:TEMP | Join-Path -ChildPath 'RemoteRunner';

        if (-not (Test-Path -Path $Local:Folder)) {
            Invoke-Verbose "Creating directory $Local:Folder";

            try {
                New-Item -Path $Local:Folder -ItemType Directory -ErrorAction Stop | Out-Null;
            } catch {
                Invoke-Error "Failed to create directory $Local:Folder";
                Invoke-FailedExit -ExitCode $Script:FAILED_WRITE -ErrorRecord $_;
            }
        }

        return $Local:Folder;
    }
}

function Get-CachableResponse {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [String]$Local:Folder = Get-RunnerFolder;
        [String]$Local:CachePath = $Local:Folder | Join-Path -ChildPath 'cached.json';

        if (Test-Path -Path $Local:CachePath) {
            [TimeSpan]$Local:CacheAge = (Get-Date) - (Get-Item -Path $Local:CachePath).CreationTime;

            if ($NoCache -or $Local:CacheAge.Minutes -gt 5) {
                Invoke-Verbose "Cache is $Local:CacheAge minutes old, removing and re-creating.";
                try {
                    Remove-Item -Path $Local:CachePath | Out-Null;
                } catch {
                    Invoke-Error "Failed to remove the cache file $Local:CachePath";
                    Invoke-FailedExit -ExitCode $Script:FAILED_WRITE -ErrorRecord $_;
                }
            } else {
                Invoke-Verbose "Cache is less than 5 minutes old, skipping api calls and assuming it's the latest version.";
            }
        }

        if (-not (Test-Path -Path $Local:CachePath)) {
            Invoke-Verbose "Cache file not found, creating a new one.";
            [String]$Local:Url = 'https://api.github.com/repos/AMTSupport/tools/releases';
            try {
                $ErrorActionPreference = 'Stop';

                Invoke-WebRequest -Uri $Local:Url -OutFile $Local:CachePath -UseBasicParsing | Out-Null;
            } catch {
                Invoke-FailedExit -ExitCode $Script:FAILED_RESPONSE -ErrorRecord $_;
            }
        }


        [HashTable[]]$Local:CacheContent = Get-Content -Path $Local:CachePath | ConvertFrom-Json -AsHashtable;
        return $Local:CacheContent;
    }
}

function Get-VersionComparable(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Version
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Concat; }

    process {
        [Int]$Local:Index = $Version.LastIndexOf("-v");
        if ($Local:Index -eq -1) {
            throw "Failed to get the version comparable for $Local:Version."
        }

        [String]$Local:Trunicated = $Local:Version.Substring($Index + 2);
        [String[]]$Local:Split = $Local:Trunicated.Split('.');
        [String]$Local:Concat = $Local:Split -join '';

        return $Local:Concat;
    }
}

function Get-LatestRelease(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Program
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:LatestRelease; }

    process {
        [HashTable[]]$Local:Releases = Get-CachableResponse;
        $Local:ProgramReleases = $Local:Releases | Where-Object { $_.tag_name -like "$Program-v*" };

        if ($null -eq $Local:ProgramReleases -or $Local:ProgramReleases.Count -eq 0) {
            Invoke-FailedExit -ExitCode $Script:FAILED_MISSING_RELEASES;
        }

        if ($Local:ProgramReleases.Count -eq 1) {
            [HashTable]$Local:LatestRelease = $Local:ProgramReleases[0];
        } else {
            [HashTable[]]$Local:SortedReleases = $Local:ProgramReleases | Sort-Object { Get-VersionComparable -Version $_.tag_name } -Descending;
            [HashTable]$Local:LatestRelease = $Local:SortedReleases | Select-Object -First 1;

            Invoke-Debug "Sorted Releases: $($Local:SortedReleases | ForEach-Object { $_.tag_name })";
            Invoke-Debug "Latest Release: $($Local:LatestRelease.tag_name)";
        }

        return $Local:LatestRelease;
    }
}

function Get-ExecutableArtifact(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Program,

    [Parameter(Mandatory)]
    [HashTable]$Release
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:ExecutableArtifact; }

    process {
        #region - Setup Variables for finding the correct artifact
        # Get the Executable Suffix for the current system
        [String]$Local:Architecture = switch ($Env:PROCESSOR_ARCHITECTURE) {
            "AMD64" { "x86_64" }
            "x86" { "i686" }
            default { Invoke-FailedExit -ExitCode $Script:FAILED_MISSING_ARCHITECTURE; }
        };

        # https://github.com/PowerShell/PowerShell/issues/6347#issuecomment-372072077
        [Boolean]$Local:IsOSWindows = $env:OS -eq 'Windows_NT' -or $IsWindows;
        [String]$Local:OperatingSystem = if ($Local:IsOSWindows) {
            "windows"
        } elseif ($IsLinux) {
            "linux"
        } elseif ($IsMacOS) {
            "macos"
        } else {
            Invoke-FailedExit -ExitCode $Script:FAILED_MISSING_OS;
        };
        #endregion - Setup Variables for finding the correct artifact

        Invoke-Info -Message "Getting the latest release of $Program for $Local:Architecture-$Local:OperatingSystem.";

        $Local:Artifacts = $Release.assets;
        If ($Local:Artifacts.Count -eq 0) {
            Invoke-FailedExit -ExitCode $Script:FAILED_MISSING_ARTIFACTS;
        }

        $Local:ExecutableArtifact = $Local:Artifacts | Where-Object { $_.name -like "$Program-$Local:Architecture-$Local:OperatingSystem*" };
        if ($null -eq $Local:ExecutableArtifact) {
            Invoke-FailedExit -ExitCode $Script:FAILED_MISSING_EXECUTABLE;
        }

        return $Local:ExecutableArtifact;
    }
}

# TODO :: Caching
function Get-DownloadedExecutable(
    [Parameter(Mandatory)]
    [ValidateScript({ $_.ContainsKey('name') -and $_.ContainsKey('browser_download_url') })]
    [HashTable]$Artifact
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:ExecutablePath; }

    process {
        [String]$Local:Parent = Get-RunnerFolder;
        [String]$Local:ExecutablePath = $Local:Parent | Join-Path -ChildPath $Artifact.name;
        [String]$Local:DownloadUrl = $Artifact.browser_download_url;

        try {
            Invoke-WebRequest -Uri $Local:DownloadUrl -OutFile $Local:ExecutablePath -UseBasicParsing | Out-Null;
        } catch {
            Invoke-FailedExit -ExitCode $Script:FAILED_DOWNLOAD -ErrorRecord $_;
        }

        return $Local:ExecutablePath;
    }
}

function Invoke-Executable(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Path,

    [Parameter()]
    [String[]]$Arguments
) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        try {
            # We can't use the ArgumentList parameter with an empty list so we need to check if it's null or empty.
            if ($null -eq $Arguments -or $Arguments.Count -eq 0) {
                Start-Process -FilePath $Path -Wait -NoNewWindow;
            } else {
                Start-Process -FilePath $Path -ArgumentList $Arguments -Wait -NoNewWindow;
            }
        } catch {
            Invoke-Error "Failed to execute ``$Path``";
            Invoke-FailedExit -ExitCode $Script:FAILED_EXECUTION -ErrorRecord $_;
        }
    }
}

Import-Module $PSScriptRoot/../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    $ErrorActionPreference = 'Stop';
    #region - Error Codes

    $Script:FAILED_WRITE = Register-ExitCode 'Failed to write to the file system.';

    $Script:FAILED_RESPONSE = Register-ExitCode 'Failed to get a response from the API.';
    $Script:FAILED_DOWNLOAD = Register-ExitCode 'There was an issue while downloading the executable.';

    $Script:FAILED_MISSING_RELEASES = Register-ExitCode 'Unable to find any releases for the repository.';
    $Script:FAILED_MISSING_ARTIFACTS = Register-ExitCode 'Unable to find any artifacts for the current release.';
    $Script:FAILED_MISSING_EXECUTABLE = Register-ExitCode 'Unable to find an executable artifact for the current system.';

    $Script:FAILED_MISSING_ARCHITECTURE = Register-ExitCode "Unable to find executable to match the current architecture. (${Env:PROCESSOR_ARCHITECTURE})";
    $Script:FAILED_MISSING_OS = Register-ExitCode "Unable to find executable to match the current operating system. (${Env:OS})";

    $Script:FAILED_EXECUTION = Register-ExitCode 'There was an issue while running the executable.';

    #endregion - Error Codes

    [HashTable]$Local:LatestRelease = Get-LatestRelease -Program $ProgramName;
    $Local:Artifact = Get-ExecutableArtifact -Program $ProgramName -Release $Local:LatestRelease;
    $Local:ExecutablePath = Get-DownloadedExecutable -Artifact $Local:Artifact;

    Invoke-Executable -Path $Local:ExecutablePath -Arguments $Arguments;
}
