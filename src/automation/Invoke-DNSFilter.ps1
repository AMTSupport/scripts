#Requires -RunAsAdministrator
#Requires -Version 5.1

Using module ../common/Environment.psm1
Using module ../common/Scope.psm1
Using module ../common/Logging.psm1
Using module @{
    ModuleName    = 'PackageManagement';
    ModuleVersion = '1.4.8.1';
}

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Install", "Check", "Uninstall")]
    [String]$Action,

    [Parameter(HelpMessage = "The site key for the DNS Filter account.")]
    [String]$SiteKey
)

$Script:RegistryPath = "HKLM:\SOFTWARE\DNSAgent\Agent"

class Result {
    [Int]$Code
    [Object]$Output
    [System.Management.Automation.ErrorRecord]$Err

    Result([Object]$Output, [System.Management.Automation.ErrorRecord]$Err, [Int]$Code) {
        $this.Code = if ($Code) { $Code } elseif ($Err) { $Err.Exception.HResult } else { 0 }
        $this.Output = $Output
        $this.Err = $Err
    }

    static [Result]Ok([Object]$Output) {
        return [Result]::new($Output, $null, 0)
    }

    static [Result]Err([System.Management.Automation.ErrorRecord]$Err, [Int]$Code) {
        return [Result]::new($null, $Err, $Code)
    }

    [Object]unwrap() {
        return $this.Output
    }

    [System.Management.Automation.ErrorRecord]unwrap_err() {
        return $this.Err
    }

    [bool]is_ok() {
        return $this.Code -eq 0
    }

    [bool]is_err() {
        return ($this.Code -ne 0) -or ($this.Err)
    }
}

function Invoke-DownloadLatest {
    [CmdletBinding()]
    [OutputType([Result])]
    param()

    $Destination = "$env:windir\Temp\DNS_Agent_Setup.msi"
    if (Test-Path $Destination -PathType Leaf) {
        $LastWriteTime = (Get-Item $Destination).LastWriteTime
        if ($LastWriteTime -gt (Get-Date).AddDays(-1)) {
            Invoke-Verbose "Using cached installer at $Destination"
            return [Result]::Ok($Destination)
        }
    }

    try {
        $Uri = "https://download.dnsfilter.com/User_Agent/Windows/DNS_Agent_Setup.msi"
        Invoke-Info "Downloading $Uri to $Destination"
        Invoke-WebRequest -Uri $Uri -OutFile $Destination -ErrorAction Stop
    } catch {
        Invoke-Error "Failed to download $Uri to $Destination"
        return [Result]::Err($_, 999)
    }

    return [Result]::Ok($Destination)
}

function Install-DnsFilterAgent {
    begin { Enter-Scope }
    end { Exit-Scope }

    process {
        $DownloadResult = Invoke-DownloadLatest
        if ($DownloadResult.is_err()) {
            return $DownloadResult
        }
        $Destination = $DownloadResult.unwrap()

        try {
            Invoke-Info "Attempting to install from [$Destination]"
            $MsiExecDNS = Start-Process msiexec -PassThru -Wait -ArgumentList "/qn", "/i", $Destination, "NKEY=$SiteKey"
            $InstallResult = $MsiExecDNS.ExitCode
            Invoke-Info "Install result: $InstallResult"

            if ($InstallResult -ne 0) {
                Invoke-Error "Failed to install from [$Destination] due to error code [$InstallResult]"
                return [Result]::Err($_, $InstallResult)
            }
        } catch {
            Invoke-Error "Failed to install from [$Destination]"
            return [Result]::Err($_, 888)
        }

        return [Result]::Ok("Installed")
    }
}

function Uninstall-DnsFilterAgent {
    begin { Enter-Scope }
    end { Exit-Scope }

    process {
        try {
            Invoke-Info "Attempting to uninstall DNS Filter"
            Get-Package -Name "DNS Agent" | Uninstall-Package -Force -ErrorAction Stop | Out-Null
        } catch {
            Invoke-Error "Failed to uninstall DNS Filter"
            return [Result]::Err($_, 888)
        }

        return [Result]::Ok("Uninstalled")
    }

}

function Get-AgentStatus {
    begin { Enter-Scope }
    end { Exit-Scope }

    process {
        if ((Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*).DisplayName -contains "DNS Agent") {
            Invoke-Info "Application is installed"
        } else {
            Invoke-Info "DNS Filter not installed"
            return [Result]::Err($null, 777)
        }

        if ((Get-Service -Name "DNS Agent").Status -eq "Running") {
            Invoke-Info "Service is running"
        } else {
            Invoke-Error "DNS Filter installed but Service is not running"
            return [Result]::Err($null, 666)
        }

        $RegValue = "NetworkKey"
        $NetworkKey = (Get-ItemProperty -Path $Script:RegistryPath -Name $RegValue).$RegValue
        if ($NetworkKey -eq $SiteKey) {
            Invoke-Info "SiteKey is correct"
        } else {
            Invoke-Error "SiteKey is incorrect"
            return [Result]::Err($null, 1639)
        }

        return [Result]::Ok("Success")

        # TODO: Look into using the API to check the status of this machine with the dashboard
        # FIXME: This needs a permanent API key, currently only able to figure out a jwt token
        # $Uri = https://api.dnsfilter.com/v1/user_agents?search=$env:COMPUTERNAME&type=agents
        # $DashboardStatus = Invoke-WebRequest -Uri $Uri -Headers @{"accept"="application/json"} -ErrorAction Stop
    }
}

function Test-IsAgentOutdated {
    $DownloadResult = Invoke-DownloadLatest
    if ($DownloadResult.is_err()) {
        return $DownloadResult
    }
    $MsiFile = $DownloadResult.unwrap()

    $LatestVersionResult = Get-MsiProperty -File $MsiFile -Property "ProductVersion";
    if ($LatestVersionResult.is_err()) {
        return $LatestVersionResult
    }
    $LatestVersion = $LatestVersionResult.unwrap().Split(".")[0..2] -join "."
    Invoke-Verbose "Latest Version: $LatestVersion"

    $CurrentVersion = (Get-ItemProperty -Path $Script:RegistryPath -Name "Version").Version
    Invoke-Verbose "Current Version: $CurrentVersion"

    return [Result]::Ok($CurrentVersion -ne $LatestVersion)
}

# based on https://github.com/bastienperez/PowerShell-Toolbox/blob/master/Get-MSIFileInformation.ps1
function Get-MsiProperty {
    [CmdletBinding()]
    [OutputType([Result])]
    param(
        [string]$File,
        [string]$Property
    )

    begin { Enter-Scope }
    end { Exit-Scope }

    process {
        $WindowsInstallerObject = New-Object -ComObject WindowsInstaller.Installer
        $MsiDatabase = $WindowsInstallerObject.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $WindowsInstallerObject, @($MsiFile, 0))

        $View = $null
        $Query = "SELECT Value FROM Property WHERE Property = '$($property)'"
        $View = $MsiDatabase.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $MsiDatabase, ($Query))
        $View.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $View, $null) | Out-Null
        $Record = $View.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $View, $null)

        try {
            $Value = $Record.GetType().InvokeMember('StringData', 'GetProperty', $null, $Record, 1)
        } catch {
            Invoke-Error "Unable to get '$property' $($_.Exception.Message)"
            return [Result]::Err($_, 999)
        }

        return [Result]::Ok($Value)
    }
}

Invoke-RunMain $PSCmdlet {
    switch ($Action) {
        "Install" {
            if ($null -eq $SiteKey) {
                Invoke-Error "SiteKey is required for installation."
                exit 1
            }

            $CurrentStatus = Get-AgentStatus
            if ($CurrentStatus.is_ok()) {
                Invoke-Info "DNS Filter is already installed."

                $OutdatedResult = Test-IsAgentOutdated
                if ($OutdatedResult.is_err()) {
                    return $OutdatedResult.unwrap_err()
                }

                if ($OutdatedResult.is_ok() -and -not $OutdatedResult.unwrap()) {
                    Invoke-Info "DNS Filter is up to date."
                    exit 0
                }

                Invoke-Info "Agent is outdated, re-running installer"
            }

            if ($CurrentStatus.is_err() -and $CurrentStatus.Code -eq 1639) {
                Invoke-Info "Uninstalling DNS Filter due to mismatching SiteKey."
                $UninstallResult = Uninstall-DnsFilterAgent

                if ($UninstallResult.is_ok()) {
                    Invoke-Info "DNS Filter uninstalled successfully."
                } else {
                    Invoke-Error "DNS Filter uninstallation failed."
                    if ($UninstallResult.is_err()) { Invoke-Error "Error: $($UninstallResult.Err)" }
                    exit $UninstallResult.Code
                }
            } elseif ($CurrentStatus.is_err() -and $CurrentStatus.Code -ne 777) {
                exit $CurrentStatus.Code
            }

            $InstallResult = Install-DnsFilterAgent
            if ($InstallResult.is_ok()) {
                Invoke-Info "DNS Filter installed successfully."
            } else {
                Invoke-Error "DNS Filter installation failed."
                if ($InstallResult.is_err()) { Invoke-Error "Error: $($InstallResult.Err)" }

                switch ($InstallResult.Code) {
                    999 { Invoke-Error "Failed to download installer." }
                    888 { Invoke-Error "Failed to install." }
                    1639 { Invoke-Error "Missing or Invalid SiteKey." }
                    default { Invoke-Error "Unknown error code: $($InstallResult.Code)" }
                }

                exit $InstallResult.Code
            }

            # Due to an issue with the installation, we may have to manually start the service again.
            Start-Sleep 5

            $CurrentStatus = Get-AgentStatus
            if ($CurrentStatus.is_ok()) {
                Invoke-Info "DNS Filter has installed and is running successfully."
            } elseif (Start-Service -Name "DNS Agent" -ErrorAction SilentlyContinue) {
                Invoke-Info "DNS Filter encountered an issue on first start, but was able to be recovered."
            } else {
                Invoke-Error "DNS Filter installation completed without error but the agent is not running."
                exit $CurrentStatus.Code
            }
        }
        "Check" {
            $CurrentStatus = Get-AgentStatus
            if ($CurrentStatus.is_ok()) {
                Invoke-Info "DNS Filter is installed and running."
            } else {
                Invoke-Error "DNS Filter is not installed or is not running."
                if ($CurrentStatus.Err) { Invoke-Error "Error: $($CurrentStatus.Err)" }
                exit $CurrentStatus.Code
            }

            $OutdatedResult = Test-IsAgentOutdated
            if ($OutdatedResult.is_err()) {
                return $OutdatedResult.unwrap_err()
            }

            if (-not $OutdatedResult.unwrap()) {
                Invoke-Info "DNS Filter is up to date."
            } else {
                Invoke-Error "DNS Filter is outdated."
            }
        }
        default {
            Invoke-Error "Invalid action: $Action"
            exit 1
        }
    }
}
