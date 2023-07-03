<#
.SYNOPSIS
    This cleaner script is used to remove leftover files and folders from the EDR & EcoSystem agent.

.NOTES
    This cannot be ran from a background terminal or system account since we need to use the winget command.
    This will not run the SentinelCleaner, or the SentinelOneInstaller as we cannot distribute those files.
    This should be ran after EDR Has being disabled from the dashboard.

.PARAMETER dryrun
    This will not modify any files or programs, but will show you what it would have done.

.PARAMETER Verbose
    This will enable verbose output.
#>

# Requires -RunAsAdministrator
#Requires -Version 5.1

Param (
    [Parameter(Mandatory = $false)]
    [switch]$dryrun = $false
)


function parseInput() {
    If ($VerbosePreference) {
        Write-Host "[VERBOSE] Verbose mode enabled."
    }

    If ($dryrun) {
        Write-Host "[DRY] Dry run mode enabled."
    }
}

function installWinget() {
    If (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Winget is already installed."
        return
    }

    if ($dryrun) {
        Write-Host "[DRY] Would required to install winget."
        return
    }

    $winget_package = "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe"
    Write-Host "Installing winget..."

    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage $winget_package
    } catch {
        Write-Host "Failed to install winget";
        Exit 1002
    }

    Write-Host "Winget installed."
}

function validateRunnable() {
    If (-Not (Test-Path "C:\Program Files (x86)\Advanced Monitoring Agent")) {
        Write-Host "There are no RMM Agents installed on this machine."

        if ($dryrun) {
            Write-Host "[DRY] Would have failed due to no RMM Agent being installed."
        } else {
            Exit 1001
        }
    }
}

function prepare() {
    $script:package_id = "{3A399BFE-2ABA-488A-A12C-F9626142D029}_is1"
    $script:winget_command = "winget uninstall --accept-source-agreements --disable-interactivity --force --exact --id `"$($script:package_id)`""

    $script:agentFolder = "C:\Program Files (x86)\Advanced Monitoring Agent"
    $script:ecosystemFolder = "SolarWinds MSP\Ecosystem Agent"
    $script:items = @(
        "$($agentFolder)\ecosystem_install.log",
        "$($agentFolder)\downloads\EcosystemInstall.exe",
        "$($agentFolder)\feature_20.log",
        "$($agentFolder)\featureres\feature_20.dll",
        "C:\ProgramData\$($ecosystemFolder)",
        "C:\Program Files\$($ecosystemFolder)"
    )
}

function clean() {
    Write-Host "Going to run the following command: $($script:winget_command)"
    Write-Host "This will uninstall the Ecosystem and all of its components."
    Write-Host "Press any key to continue, or CTRL+C to cancel."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host "Running command..."

    If ($dryrun) {
        Write-Host "[DRY] Would have ran $($script:winget_command)"
    } else {
        Invoke-Expression $script:winget_command
    }

    ForEach ($item in $script:items) {
        If (Test-Path $item) {
            if ($dryrun) {
                Write-Host "[DRY] Would have removed $($item)"
                continue
            }

            Remove-Item $item -Force
        }
    }
}

function main() {
    parseInput
    validateRunnable
    installWinget
    prepare
    clean
}

main
