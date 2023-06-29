#Requires -Version 5.1

<#
.DESCRIPTION

#>

# Section start :: Set variables

$DefaultPrograms = @("GoogleChrome", "adobereader")

# Section end :: Set variables

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
    [Commandline]$Commandline

    Logger([Commandline]$CommandlineIn) {
        $this.Commandline = $CommandlineIn

        if ((Test-Path -Path ([Logger]::LogFilePath)) -eq $false) {
            New-Item -Path ([Logger]::LogFilePath) -ItemType File
        }
    }

    [Void] static WriteLog ([String]$Message, [String]$Type) {
        $logMessage = [Logger]::LogFormat -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"),$Type,$Message
        $logMessage | Out-File -FilePath ([Logger]::LogFilePath) -Append
        $logMessage | Write-Host
    }

    [Void] Info ([String]$Message) {
        [Logger]::WriteLog($Message, "INFO")
    }

    [Void] static Error ([String]$Message) {
        [Logger]::WriteLog($Message, "ERROR")
    }

    [Void] static Verbose ([String]$Message) {
        [Logger]::WriteLog($Message, "VERBOSE")
        return

        # if ($this.Commandline -eq $null) {
            # return
        # if ($this.Commandline.IsVerbose()) {
        #     $this.WriteLog($Message, "VERBOSE")
        # }
    }
}

Class Argument {
    [Char]$Short
    [String]$Long
    [Boolean]$Required
    [Boolean]$TakesValue
    [Boolean]$TakesMany

    Argument([Char]$ShortIn, [String]$LongIn, [Boolean]$RequiredIn, [Boolean]$TakesValueIn, [Boolean]$TakesManyIn) {
        $this.Short = $ShortIn
        $this.Long = $LongIn
        $this.Required = $RequiredIn
        $this.TakesValue = $TakesValueIn
        $this.TakesMany = $TakesManyIn
    }

    [Boolean] matches([String]$Tag) {
        return ($this.Short -eq $Tag -or $this.Long -eq $Tag)
    }
}

Class ProcessedArgument {
    [Argument]$Base

    ProcessedArgument([Argument]$BaseIn) {
        $this.Base = $BaseIn
    }
}

Class PresentArgument : ProcessedArgument {
    PresentArgument([Argument]$BaseIn) : base($BaseIn) { }
}

Class AbsentArgument : ProcessedArgument {
    AbsentArgument([Argument]$BaseIn) : base($BaseIn) { }
}

Class ValuedArgument : ProcessedArgument {
    [String]$Value

    ValuedArgument([Argument]$BaseIn, [String]$ValueIn) : base($BaseIn) {
        $this.Value = $ValueIn
    }
}

Class ArrayValuedArgument : ProcessedArgument {
    [String[]]$Value

    ArrayValuedArgument([Argument]$BaseIn, [String[]]$ValueIn) : base($BaseIn) {
        $this.Value = $ValueIn
    }
}

Class Commandline {
    static [String]$Regex = "^(-{1,2})(?<Tag>[a-zA-Z]+)$"
    static [PSCustomObject]$ArgumentsBase = @{
        DryRun = [Argument]::new("d", "dry", $false, $false, $false)
        Verbose = [Argument]::new("v", "verbose", $false, $false, $false)
        Install = [Argument]::new("S", "install", $false, $true, $true)
        Uninstall = [Argument]::new("R", "uninstall", $false, $true, $true)
        Update = [Argument]::new("U", "update", $false, $false, $false)
    }
    [PSCustomObject]$Arguments = @{}

    Commandline([String[]]$ArgumentsIn) {
        $listedArguments = @([Commandline]::ArgumentsBase.GetEnumerator())
        $matching = $null
        $appendingList = $null

        foreach ($arg in $ArgumentsIn) {
            [Logger]::Verbose("Processing argument: $arg")

            if ($matching -ne $null) {
                [Logger]::Verbose("Looking for value of argument: $($matching.Key)")

                if ($arg -match [Commandline]::Regex) {
                    [Logger]::Error("Found argument when looking for value: $arg; exiting...")
                    exit 1
                }

                if ($matching.Value.TakesMany) {
                    [Logger]::Verbose("Appending $arg to value of argument: $($matching.Key)")
                    if ($appendingList -eq $null) {
                        $appendingList = @($arg)
                    } else {
                        $appendingList += $arg
                    }

                    continue
                } else {
                    [Logger]::Verbose("Setting value of argument: $($matching.Key)")
                    $processed = [ValuedArgument]::new($matching.Value, $arg)
                }

            } else {
                if ($arg -notmatch [Commandline]::Regex) {
                    [Logger]::Error("Invalid Argument Regex: $arg; exiting...")
                    exit 1
                }

                $tag = $Matches.Tag

                $matching = $listedArguments | Where-Object { $_.Value.matches($tag) }
                if ($matching -eq $null) {
                    [Logger]::Error("No matching argument found: $arg; exiting...")
                    exit 1
                }

                [Logger]::Verbose("Found matching argument: $($matching.Key)")

                if ($matching.Value.TakesValue) {
                    [Logger]::Verbose("Argument takes value: $($matching.Key)")
                    if ($matching.Value.TakesMany) {
                        [Logger]::Verbose("Argument takes many values: $($matching.Key)")
                    }

                    continue
                }

                $processed = [PresentArgument]::new($matching.Value)
            }

            $this.Arguments[$matching.Key] = $processed
            $matching = $null
        }

        if ($appendingList -ne $null -and $appendingList -gt 0) {
            [Logger]::Verbose("Setting value of argument: $($matching.Key)")
            $processed = [ArrayValuedArgument]::new($matching.Value, $appendingList)
            $this.Arguments[$matching.Key] = $processed
        }

        foreach ($arg in $listedArguments) {
            if ($arg.Value.Required -and $this.Arguments[$arg.Key] -eq $null) {
                [Logger]::Error("Required Argument not present: $($arg.Key); exiting...")
                exit 1
            }

            if ($this.Arguments[$arg.Key] -eq $null) {
                $this.Arguments[$arg.Key] = [AbsentArgument]::new($arg.Value)
            }
        }
    }

    [String[]] Uninstall() {
        $rawPrograms = $this.Arguments["Uninstall"]
        if ($rawPrograms -is [AbsentArgument]) {
            return $null
        }

        return $rawPrograms.Value -As [String[]]
    }


    [String[]] Install() {
        $rawPrograms = $this.Arguments["Install"]
        if ($rawPrograms -is [AbsentArgument]) {
            return $null
        }

        return $rawPrograms.Value -As [String[]]
    }

    [Boolean] Updating() {
        return ($this.Arguments["Update"] -is [PresentArgument])
    }

    [Boolean] IsDryRun() {
        return ($this.Arguments["DryRun"] -is [PresentArgument])
    }

    [Boolean] IsVerbose() {
        return ($this.Arguments["Verbose"] -is [PresentArgument])
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

function Install(
    [Parameter(Mandatory)]
    [Commandline]$Commandline,
    [Parameter(Mandatory)]
    [String[]]$Needed
) {
    $ChocoCommand = "choco install --yes --acceptlicense --no-progress"

    if ($Commandline.isDryRun()) {
        $ChocoCommand = "$ChocoCommand --noop"
    }

    $ChocoCommand = "$ChocoCommand $($Needed -join " ")"
    Invoke-Expression $ChocoCommand
}

function Uninstall(
    [Parameter(Mandatory)]
    [Commandline]$Commandline,
    [Parameter(Mandatory)]
    [String[]]$Removing
) {
    $ChocoCommand = "choco uninstall --yes --no-progress"

    if ($Commandline.isDryRun()) {
        $ChocoCommand = "$ChocoCommand --noop"
    }

    $ChocoCommand = "$ChocoCommand $($Removing -join " ")"
    Invoke-Expression $ChocoCommand
}

function Update([Parameter(Mandatory)] [Commandline]$Commandline) {
    $ChocoCommand = "choco upgrade all --yes --no-progress"

    if ($Commandline.isDryRun()) {
        $ChocoCommand = "$ChocoCommand --noop"
    }

    Invoke-Expression $ChocoCommand
}

# Section end :: Choco Functions

# Section start :: Main Functions

function Init ([Parameter()] [String[]]$args) {
    process {
        $Init = [PSCustomObject]@{
            Commandline = $null
            Logger = $null
        }

        $Init.Commandline = [Commandline]::new($args)
        $Init.Logger = [Logger]::new($Init.Commandline)
        $Init.Logger.Info("Initialising...")

        if ($Init.Commandline.IsDryRun()) {
            $Init.Logger.Info("Dry run enabled.")
        }

        if ($Init.Commandline.IsVerbose()) {
            $Init.Logger.Info("Verbose output enabled.")
        }

        return $Init
    }
}

function InstallRequirements ([Parameter(Mandatory = $true)] [PSCustomObject]$Init) {
    process {
        if ((Get-Command -Name choco -ErrorAction SilentlyContinue) -ne $null) {
            [Logger]::Verbose("Chocolatey is already installed. Skipping installation.")
            return
        }

        # Test for present Chocolatey files
        if (Test-Path -Path "$($env:SystemDrive)\ProgramData\Chocolatey") {
            [Logger]::Verbose("Chocolatey files found, please remove them before continuing.")
            exit 1
        }

        $Init.Logger.Info("Installing requirements...")

        # [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Set-ExecutionPolicy Bypass -Scope Process -Force
        if ($Init.Commandline.IsDryRun() -ne $true) {
            iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        }
    }
}

function InstallPackages ([Parameter(Mandatory = $true)] [PSCustomObject]$Init) {

    process {
        $Wanted = $Init.Commandline.Install()
        if ($Wanted -eq $null) {
            [Logger]::Verbose("No packages to install.")
            return
        }

        $Init.Logger.Info("Installing packages...")
        $Init.Logger.Info("Wanted Packages: $($Wanted -join ', ')")
        $Needed = @()

        foreach ($program in $Wanted) {
            if (Installed $program) {
                $Init.Logger.Info("Package already installed: ``$program``")
                continue
            }

            if ($program -match "^default(s)?$") {
                $Init.Logger.Info("Installing default packages...")
                $DefaultPrograms | ForEach-Object { $Needed += $_ }
                continue
            }

            if ((Exists $program) -eq $false) {
                [Logger]::Error("Package not found: ``$program``")
                exit 1
            }

            $Needed += $program
        }

        if ($Needed.Count -eq 0) {
            $Init.Logger.Info("All packages already installed.")
            return
        }

        $Init.Logger.Info("Packages to install: $($Needed -join ', ')")
        Install $Init.Commandline $Needed
    }
}

function UninstallPackages ([Parameter(Mandatory = $true)] [PSCustomObject]$Init) {
    process {
        $Unwanted = $Init.Commandline.Uninstall()
        if ($Unwanted -eq $null) {
            [Logger]::Verbose("No packages to uninstall.")
            return
        }

        $Init.Logger.Info("Uninstalling packages...")
        $Init.Logger.Info("Unwanted Packages: $($Unwanted -join ', ')")
        $Removing = @()

        $Unwanted | ForEach-Object {
            if ((Installed $_) -eq $false) {
                $Init.Logger.Info("Package not installed: ``$_``")
                continue
            }

            $Removing += $_
        }

        if ($Removing.Count -eq 0) {
            $Init.Logger.Info("No packages to uninstall.")
            return
        }

        $Init.Logger.Info("Packages to uninstall: $($Removing -join ', ')")
        Uninstall $Init.Commandline $Removing
    }
}

function UpdatePackages ([Parameter(Mandatory = $true)] [PSCustomObject]$Init) {
    process {
        if ($Init.Commandline.Updating() -eq $false) {
            [Logger]::Verbose("Not updating packages.")
            return
        }

        $Init.Logger.Info("Updating packages...")
        Update $Init.Commandline
    }
}

# Section end :: Functions

# Section start :: Main

$Init = (Init $args)
InstallRequirements $Init
InstallPackages $Init
UninstallPackages $Init
UpdatePackages $Init

# Section end :: Main
