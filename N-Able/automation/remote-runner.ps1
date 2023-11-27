#Requires -Version 5.1

Param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ProgramName,

    [Parameter(ValueFromRemainingArguments)]
    [String[]]$Arguments,

    [switch]$NoCache
)

#region - Error Codes

$Script:NULL_ARGUMENT = 1000;
$Script:FAILED_TO_LOG = 1001;

$Script:WEB_REQUEST_FAILED = 1010;
$Script:NO_RELEASES_FOUND = 1011;
$Script:NO_ARTIFACTS_FOUND = 1012;

#endregion - Error Codes

#region - Utility Functions

function Local:Get-ScopeNameFormatted(
    [Parameter(Mandatory)][ValidateNotNull()]
    [System.Management.Automation.InvocationInfo]$Invocation
) {
    [String]$ScopeName = $Invocation.MyCommand.Name;
    [String]$ScopeName = if ($null -ne $ScopeName) { "Scope: $ScopeName" } else { 'Scope: Unknown' };

    return $ScopeName;
}

function Enter-Scope(
    [Parameter(Mandatory)][ValidateNotNull()]
    [System.Management.Automation.InvocationInfo]$Invocation
) {
    [String]$Local:ScopeName = Get-ScopeNameFormatted -Invocation $Invocation;
    [System.Collections.IDictionary]$Local:Params = $Invocation.BoundParameters;

    [String]$Local:ParamsFormatted = if ($null -ne $Params -and $Params.Count -gt 0) {
        [String[]]$ParamsFormatted = $Params.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" };
        [String]$Local:ParamsFormatted = $Local:ParamsFormatted -join "`n`t";

        "Parameters: $Local:ParamsFormatted";
    }
    else { 'Parameters: None'; }

    Write-Verbose "Entered Scope`n`t$ScopeName`n`t$ParamsFormatted";
}

function Exit-Scope(
    [Parameter(Mandatory)][ValidateNotNull()]
    [System.Management.Automation.InvocationInfo]$Invocation,

    [Object]$ReturnValue
) {
    [String]$Local:ScopeName = Get-ScopeNameFormatted -Invocation $Invocation;
    if ($null -ne $ReturnValue) {
        [String]$Local:FormattedValue = switch ($ReturnValue) {
            { $_ -is [System.Collections.Hashtable] } { "`n`t$(([HashTable]$ReturnValue).GetEnumerator().ForEach({ "$($_.Key) = $($_.Value)" }) -join "`n`t")" }
            default { $ReturnValue }
        };

        [String]$Local:ReturnValueFormatted = "Return Value: $Local:FormattedValue";
    }
    else { [String]$Local:ReturnValueFormatted = 'Return Value: None'; };

    Write-Verbose "Exited Scope`n`t$ScopeName`n`t$ReturnValueFormatted";
}

#endregion - Utility Functions

#region - Exit Functions

function Invoke-FailedExit(
    [Parameter(Mandatory)][ValidateNotNull()]
    [Int]$ExitCode,

    [System.Management.Automation.ErrorRecord]$ErrorRecord
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        If ($null -ne $ErrorRecord) {
            [System.Management.Automation.InvocationInfo]$Local:InvocationInfo = $ErrorRecord.InvocationInfo;

            [System.Exception]$Local:RootCause = $ErrorRecord.Exception;
            while ($null -ne $Local:RootCause.InnerException) {
                $Local:RootCause = $Local:RootCause.InnerException;
            }

            Write-Host -ForegroundColor Red $Local:InvocationInfo.PositionMessage;
            Write-Host -ForegroundColor Red $Local:RootCause.Message;
        }

        Exit $ExitCode;
    }
}

function Invoke-QuickExit {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        Write-Host -ForegroundColor Red 'Exiting...';
        Exit 0;
    }
}

#endregion - Exit Functions

#region - Github Functions

function Get-Folder {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:Folder; }

    process {
        [String]$Local:Folder = "$env:TEMP/RemoteRunner";
        if (-not (Test-Path -Path $Local:Folder)) {
            Write-Verbose "Creating directory $Local:Folder"
            try {
                New-Item -Path $Local:Folder -ItemType Directory -ErrorAction Stop | Out-Null
            } catch {
                Write-Error "Failed to create directory $Local:Folder" -Category PermissionDenied
                exit $Script:FAILED_WRITE
            }
        }

        if (-not (Test-Path -Path $Local:Folder)) {
            Write-Verbose "Creating directory $Local:Folder"
            New-Item -Path $Local:Folder -ItemType Directory | Out-Null
        }

        return $Local:Folder;
    }
}

function Get-CachableResponse {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:CacheContent; }

    process {
        Trap {
            Write-Host -ForegroundColor Red -Message "❌ Unkown error while getting releases for the monorepo.";
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        }

        [String]$Local:Folder = Get-Folder;
        [String]$Local:CachePath = $Local:Folder | Join-Path -ChildPath 'cached.json';

        if (Test-Path -Path $Local:CachePath) {
            [TimeSpan]$Local:CacheAge = (Get-Date) - (Get-Item -Path $Local:CachePath).CreationTime;
            if ($Local:CacheAge.Minutes -le 5 -or $NoCache) {
                Write-Verbose -Message "Cache is less than 5 minutes old, skipping api calls and assuming it's the latest version.";
                $Local:Cache = Get-Content -Path $Local:CachePath | ConvertFrom-Json;
                return $Local:Cache;
            }

            Write-Verbose -Message "Cache is $Local:CacheAge minutes old, removing and re-creating.";
            Remove-Item -Path $Local:CachePath | Out-Null;
        }

        [String]$Local:Url = 'https://api.github.com/repos/AMTSupport/tools/releases';
        try {
            $ErrorActionPreference = 'Stop';

            Invoke-WebRequest -Uri $Local:Url -OutFile $Local:CachePath -UseBasicParsing | Out-Null;
            $Local:CacheContent = Get-Content -Path $Local:CachePath | ConvertFrom-Json;
        } catch {
            Write-Host -ForegroundColor Red -Object "Failed to get releases for the monorepo.";
            exit $Script:WEB_REQUEST_FAILED;
        }

        return $Local:CacheContent;
    }
}

function Get-VersionComparable([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Version) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:Concat; }

    process {
        [Int]$Local:Index = $Version.LastIndexOf("-v");
        if ($Local:Index -eq -1) {
            throw "Failed to get the version comparable for $Local:Version."
        }

        $Local:Trunicated = $Local:Version.Substring($Index + 2);
        $Local:Split = $Local:Trunicated.Split('.');
        $Local:Concat = $Local:Split -join '';

        return $Local:Concat;
    }
}

function Get-LatestRelease([Parameter(Mandatory)][ValidateNotNullOrEmpty()][String]$Program) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:LatestRelease; }

    process {
        Trap {
            Write-Host -ForegroundColor Red -Message "Unkown error while getting the latest release for $Program.";
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        }

        $Local:Releases = Get-CachableResponse;
        $Local:ProgramReleases = $Local:Releases | Where-Object { $_.tag_name -like "$Program-v*" };
        if ($Local:ProgramReleases.Count -eq 0) {
            Write-Host -ForegroundColor Red -Message "No releases found for $Program.";
            exit $Script:NO_RELEASES_FOUND;
        }

        $Local:SortedReleases = $Local:ProgramReleases | Sort-Object { Get-VersionComparable -Version $_.tag_name } -Descending;
        $Local:LatestRelease = $Local:SortedReleases[0];

        return $Local:LatestRelease;
    }
}

function Get-ExecutableArtifact(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
    [String]$Program,

    [Parameter(Mandatory)]
    [Object]$Release
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $Local:ExecutableArtifact; }

    process {
        Trap {
            Write-Host -ForegroundColor Red -Message "Unkown error while getting the executable artifact for $Local:Program.";
            Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
        }

        # Get the Executable Suffix for the current system
        [String]$Local:Architecture = switch ($Env:PROCESSOR_ARCHITECTURE) {
            "AMD64" { "x86_64" }
            "x86" { "i686" }
            default { Write-Error "Unknown processor architecture: $Env:PROCESSOR_ARCHITECTURE"; exit 1101 }
        };

        [String]$Local:OperatingSystem = switch ($Env:OS) {
            "Windows_NT" { "windows" }
            default { Write-Error "Unknown operating system: $Env:OS"; exit 1102 }
        };

        Write-Verbose -Message "Getting the latest release of $Program for $Local:Architecture-$Local:OperatingSystem.";

        $Local:Artifacts = $Release.assets;
        If ($Local:Artifacts.Count -eq 0) {
            Write-Host -ForegroundColor Red -Object "No artifacts found for the release of $Program.";
            Invoke-FailedExit -ExitCode $Script:NO_ARTIFACTS_FOUND;
        }

        $Local:ExecutableArtifact = $Local:Artifacts | Where-Object { $_.name -like "$Program-$Local:Architecture-$Local:OperatingSystem*" };
        if ($null -eq $Local:ExecutableArtifact) {
            Write-Host -ForegroundColor Red -Object "Could not find an executable artifact for the current system.";
            Invoke-FailedExit -ExitCode $Script:NO_ARTIFACTS_FOUND;
        }

        return $Local:ExecutableArtifact;
    }
}

# TODO :: Caching
function Get-DownloadedExecutable([Parameter(Mandatory)][Object]$Artifact) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation -ReturnValue $ExecutablePath; }

    process {
        $Parent = "$env:TEMP\RemoteRunner"
        $ExecutablePath = "$Parent\$($Artifact.name)"

        $Parent = Split-Path -Path $ExecutablePath -Parent
        if (-not (Test-Path -Path $Parent)) {
            Write-Verbose "Creating directory $Parent"
            New-Item -Path $Parent -ItemType Directory | Out-Null
        }

        try {
            $DownloadLink = $Artifact.browser_download_url
            Invoke-WebRequest -Uri $downloadLink -OutFile $ExecutablePath -UseBasicParsing | Out-Null
        } catch {
            Write-Error "Failed to download the latest release of $ProgramName."
            exit 1201
        }

        return $ExecutablePath
    }
}

function Invoke-Executable([Parameter(Mandatory)][String]$Path, [String[]]$Arguments) {
    begin { Enter-Scope $MyInvocation }

    process {
        try {
            if ($Arguments.Count -eq 0 -or $null -eq $Arguments) {
                Start-Process -FilePath $Path -Wait -NoNewWindow
            } else {
                Start-Process -FilePath $Path -ArgumentList $Arguments -Wait -NoNewWindow
            }
        } catch {
            Write-Error "Failed to execute ``$($Path)``"
            Write-Error $_
            exit 1301
        }
    }

    end { Exit-Scope $MyInvocation }
}

function Main {
    $Local:LatestRelease = Get-LatestRelease -Program $ProgramName;
    $Local:Artifact = Get-ExecutableArtifact -Program $ProgramName -Release $Local:LatestRelease;
    $Local:ExecutablePath = Get-DownloadedExecutable -Artifact $Local:Artifact;
    Invoke-Executable -Path $Local:ExecutablePath -Arguments $Arguments;
}

try {
    Main
} catch {
    Write-Error "Caught unhandled exception" -Exception $_
    exit 1401
}
