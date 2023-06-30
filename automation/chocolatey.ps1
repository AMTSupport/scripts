#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.DESCRIPTION
    Simplifies the installation and management of Chocolatey packages.
    This script is designed to be run as a scheduled task.

.PARAMETER dryrun
    If specified, the script will not make any changes to the system.
    This is useful for testing the script.

.PARAMETER runMode
    Specifies the mode to run the script in.
    Valid values are:
        - run       (This will try install the default packages and then update any avaiable packages)
        - update    (This will update any avaiable packages, or if packages are specified, update those packages only)
        - install   (This will install the specified packages only)
        - uninstall (This will uninstall the specified packages only)
#>

Param (
    [Parameter(Mandatory=$false)]
    [switch]$dryrun = $false,

    [Parameter(Mandatory=$false)]
    [ValidateSet("run", "update", "install", "uninstall")]
    [string]$runMode = "run",

    [Parameter(Mandatory=$false)]
    [string[]]$packages = @(),

    [Parameter(Mandatory=$false)]
    [string[]]$defaultPackages = @(
        "GoogleChrome",
        "adobereader",
        "displaylink"
    )
)

# Section start :: Classes

function Hold-Shutdown([Parameter] [boolean]$release = $false) {
    $process = get-process -pid $pid
    if ($release) {
        [preventor.Shutdown]::ShutdownBlockReasonDestroy($process.MainWindowHandle)
        return
    }

    [preventor.Shutdown]::ShutdownBlockReasonCreate($process.MainWindowHandle, "choco is running")
}

Class Logger {
    static [String]$LogFilePath = "$env:TEMP\Choco.log"
    static [String]$LogFormat = "[{0}|{1}] {2}"

    Logger() {
        if ((Test-Path -Path ([Logger]::LogFilePath)) -eq $false) {
            New-Item -Path ([Logger]::LogFilePath) -ItemType File
        }
    }

    static WriteLog ([String]$Message, [String]$Type) {
        $logMessage = [Logger]::LogFormat -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Type,$Message
        $logMessage | Out-File -FilePath ([Logger]::LogFilePath) -Append
        $logMessage | Write-Host
    }

    [Void] Info ([String]$Message) {
        [Logger]::WriteLog($Message, "INFO")
    }

    [Void] Error ([String]$Message) {
        [Logger]::WriteLog($Message, "ERROR")
    }

    [Void] Verbose ([String]$Message) {
        [Logger]::WriteLog($Message, "VERBOSE")
    }
}

# Section end :: Classes

# Section start :: Choco Functions

function Installed([Parameter(Mandatory)] [String]$Program) {
    $output = (choco search --exact --localonly --idonly -r $Program)
    return ($output -contains $Program)
}

function Exists([Parameter(Mandatory)] [String]$Program) {
    $output = (choco search --exact --idonly -r $Program)
    return ($output -contains $Program)
}

function Install([Parameter(Mandatory)] [String[]]$Needed) {
    $ChocoCommand = "choco install --yes --acceptlicense --no-progress"

    if ($dryrun) {
        $ChocoCommand = "$ChocoCommand --noop"
    }

    $ChocoCommand = "$ChocoCommand $($Needed -join " ")"
    Invoke-Expression $ChocoCommand
}

function Uninstall([Parameter(Mandatory)] [String[]]$Removing) {
    $ChocoCommand = "choco uninstall --yes --no-progress"

    if ($dryrun) {
        $ChocoCommand = "$ChocoCommand --noop"
    }

    $ChocoCommand = "$ChocoCommand $($Removing -join " ")"
    Invoke-Expression $ChocoCommand
}

function Update([Parameter(Mandatory=$false)] [String[]]$targets) {
    if ($null -eq $targets) {
        $targets = "all"
    } else {
        $targets = $targets -join " "
    }

    $ChocoCommand = "choco upgrade $($targets) --yes --no-progress"

    if ($dryrun) {
        $ChocoCommand = "$ChocoCommand --noop"
    }

    Invoke-Expression $ChocoCommand
}

# Section end :: Choco Functions

# Section start :: Main Functions

function InstallRequirements () {
    $script:logger.Verbose("Started running {0} function." -f $MyInvocation.MyCommand)

    if ($null -ne (Get-Command -Name choco -ErrorAction SilentlyContinue)) {
        $script:logger.Verbose("Chocolatey is already installed. Skipping installation.")
        return
    }

    # Test for present Chocolatey files
    if (Test-Path -Path "$($env:SystemDrive)\ProgramData\Chocolatey") {
        $script:logger.Error("Chocolatey files found, please remove them before continuing.")
        exit 1001
    }

    $script:logger.Info("Installing chocolatey...")

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Set-ExecutionPolicy Bypass -Scope Process -Force
    if ($dryrun -ne $true) {
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }

    $script:logger.Info("Chocolatey installed.")

    $script:logger.Verbose("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function InstallPackages ([Parameter(Mandatory)] [String[]]$packages) {
    $script:logger.Verbose("Started running {0} function." -f $MyInvocation.MyCommand)

    if ($null -eq $packages -or $packages.Count -eq 0) {
        $script:logger.Verbose("No packages to install.")
        return
    }

    $script:logger.Info("Installing packages...")
    $script:logger.Info("Wanted Packages: $($packages -join ', ')")
    $Needed = @()

    foreach ($program in $packages) {
        if (Installed $program) {
            $script:logger.Verbose("Package already installed: ``$program``")
            continue
        }

        if ((Exists $program) -eq $false) {
            $script:logger.Error("Package not found: ``$program``")
            exit 1002
        }

        $Needed += $program
    }

    if ($Needed.Count -eq 0) {
        $script:logger.Verbose("All packages already installed.")
        return
    }

    $script:logger.Verbose("Packages to install: $($Needed -join ', ')")
    Install $Needed

    $script:logger.Verbose("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function UninstallPackages ([Parameter(Mandatory)] [String[]]$packages) {
    $script:logger.Verbose("Started running {0} function." -f $MyInvocation.MyCommand)

    if ($null -eq $packages -or $packages.Count -eq 0) {
        $script:logger.Verbose("No packages to uninstall.")
        return
    }

    $script:logger.Info("Uninstalling packages...")
    $script:logger.Info("Unwanted Packages: $($packages -join ', ')")
    $Removing = @()

    $packages | ForEach-Object {
        if ((Installed $_) -eq $false) {
            $script:logger.Verbose("Package not installed: ``$_``")
            continue
        }

        $Removing += $_
    }

    if ($Removing.Count -eq 0) {
        $script:logger.Verbose("No packages to uninstall.")
    } else {
        $script:logger.Verbose("Packages to uninstall: $($Removing -join ', ')")
        Uninstall $Removing
    }

    $script:logger.Verbose("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function UpdatePackages ([Parameter(Mandatory=$false)] [String[]]$packages) {
    $script:logger.Verbose("Started running {0} function." -f $MyInvocation.MyCommand)

    $script:logger.Info("Updating packages...")
    if ($null -eq $packages -or $packages.Count -eq 0) {
        Update
    } else {
        Update $packages
    }

    $script:logger.Verbose("Completed running {0} function." -f $MyInvocation.MyCommand)
}

function main() {
    $script:logger = [Logger]::new()
    InstallRequirements

    switch ($runMode) {
        "install" {
            InstallPackages $packages
        }
        "uninstall" {
            UninstallPackages $packages
        }
        "update" {
            UpdatePackages $packages
        }
        "run" {
            InstallPackages $defaultPackages
            UpdatePackages
        }
    }
}

# Section end :: Functions

main
