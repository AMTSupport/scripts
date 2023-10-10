#Requires -Version 5.1

Param(
    [Parameter(Mandatory)]
    [string]$ProgramName,

    [Parameter(ValueFromRemainingArguments)]
    [String[]]$Arguments
)

# #region - Scope Functions

function Enter-Scope([System.Management.Automation.InvocationInfo]$Invocation) {
    $Params = $Invocation.BoundParameters
    Write-Verbose "Entered scope $($Invocation.MyCommand.Name) with parameters [$($Params.Keys) = $($Params.Values)]"
}

function Exit-Scope([System.Management.Automation.InvocationInfo]$Invocation, [Object]$ReturnValue) {
    Write-Verbose "Exited scope $($Invocation.MyCommand.Name) with return value [$ReturnValue]"
}

# #endregion Scope Functions

function Get-CachableResponse {
    begin { Enter-Scope $MyInvocation }

    process {
        $Parent = "$env:TEMP/RemoteRunner"
        $CachePath = "$Parent/cached.json"
        if (-not (Test-Path -Path $Parent)) {
            Write-Verbose "Creating directory $Parent"
            New-Item -Path $Parent -ItemType Directory | Out-Null
        }

        if (Test-Path -Path $CachePath) {
            $CacheAge = (Get-Date) - (Get-Item -Path $CachePath).CreationTime
            if ($CacheAge.Minutes -le 1) {
                Write-Host "Cache is less than 1 minute old, skipping api calls and assuming it's the latest version."
                $Cache = Get-Content -Path $CachePath | ConvertFrom-Json
                return $Cache
            }

            Remove-Item -Path $CachePath | Out-Null
        }

        $Url = "https://api.github.com/repos/AMTSupport/tools/releases"
        Invoke-RestMethod -Uri $Url -OutFile $CachePath -UseBasicParsing | Out-Null
        return Get-Content -Path $CachePath | ConvertFrom-Json
    }

    end { Exit-Scope $MyInvocation }
}

function Get-VersionComparable([String]$Version) {
    $Index = $Version.LastIndexOf("-v");
    $Trunicated = $Version.Substring($Index + 2);
    $Split = $Trunicated.Split('.');

    # Join-String was added in PowerShell 6.2
    $Concat = if ($PSVersionTable.PSVersion.Major -ge 6 -and $PSVersionTable.PSVersion.Minor -ge 2) {
        $Split | Join-String
    } else {
        $Split -join ''
    }

    return $Concat
}

function Get-LatestRelease([Parameter(Mandatory)][String]$Program) {
    begin { Enter-Scope $MyInvocation }

    process {
        try {
            # Get the releases for the monorepo
            $releases = Get-CachableResponse
        } catch {
            Write-Error "Failed to get releases for the monorepo."
            exit 1001
        }

        try {
            # Filter the releases to only include those for the desired program
            $programReleases = $releases | Where-Object { $_.tag_name -like "$ProgramName-v*" }

            # Sort the program releases by date, descending
            $programReleases = $programReleases | Sort-Object { Get-VersionComparable -Version $_.tag_name } -Descending

            # Get the latest release of the program
            $latestProgramRelease = $programReleases[0]
        } catch {
            Write-Error "Failed to get the latest release for $ProgramName."
            exit 1002
        }

        return $latestProgramRelease
    }

    end { Exit-Scope $MyInvocation }
}

function Get-ExecutableArtifact([Parameter(Mandatory)][Object]$Release) {
    begin { Enter-Scope $MyInvocation }

    process {
        # Get the Executable Suffix for the current system
        $Architecture = switch ($Env:PROCESSOR_ARCHITECTURE) {
            "AMD64" { "x86_64" }
            "x86" { "i686" }
            default { Write-Error "Unknown processor architecture: $Env:PROCESSOR_ARCHITECTURE"; exit 1101 }
        }

        $OperatingSystem = switch ($Env:OS) {
            "Windows_NT" { "windows" }
            default { Write-Error "Unknown operating system: $Env:OS"; exit 1102 }
        }

        # Get the executable artifact for the current system
        $artifacts = $latestProgramRelease.assets

        # Search for an artifact with the name of the program, the architecture, and the operating system, use like to allow for .exe ext
        $executableArtifact = $artifacts | Where-Object { $_.name -like "$ProgramName-$Architecture-$OperatingSystem*" }
        if (!$executableArtifact) {
            Write-Error "Could not find an executable artifact for the current system."
            exit 1103
        }

        return $executableArtifact
    }

    end { Exit-Scope $MyInvocation }
}

# TODO :: Caching
function Get-DownloadedExecutable([Parameter(Mandatory)][Object]$Artifact) {
    begin { Enter-Scope $MyInvocation }

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

    end { Exit-Scope $MyInvocation }
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
    $latestProgramRelease = Get-LatestRelease -Program $ProgramName
    $executableArtifact = Get-ExecutableArtifact -Release $latestProgramRelease
    $executablePath = Get-DownloadedExecutable -Artifact $executableArtifact
    Invoke-Executable -Path $executablePath -Arguments $Arguments
}

try {
    Main
} catch {
    Write-Error "Caught unhandled exception" -Exception $_
    exit 1401
}
