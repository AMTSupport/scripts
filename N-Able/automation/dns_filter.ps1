#Requires -RunAsAdministrator
#Requires -Version 5.1
#Requires -PSEdition Desktop

Param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Install", "Check", "Uninstall")]
    [string]$Action,

    [Parameter(HelpMessage = "The site key for the DNS Filter account.")]
    [string]$SiteKey
)

class Result {
    [Int]$Code
    [string]$Output
    [System.Management.Automation.ErrorRecord]$Err

    Result([string]$Output, [System.Management.Automation.ErrorRecord]$Err, [Int]$Code) {
        $this.Code = if ($Code) { $Code } elseif ($Err) { $Err.Exception.HResult } else { 0 }
        $this.Output = $Output
        $this.Err = $Err
    }

    static [Result]Ok([string]$Output) {
        return [Result]::new($Output, $null, 0)
    }

    static [Result]Err([System.Management.Automation.ErrorRecord]$Err, [Int]$Code) {
        return [Result]::new($null, $Err, $Code)
    }

    [bool]is_ok() {
        return $this.Code -eq 0
    }

    [bool]is_err() {
        return ($this.Code -ne 0) -or ($this.Err)
    }
}

#region - Scope Functions

function Enter-Scope([System.Management.Automation.InvocationInfo]$Invocation) {
    $Params = $Invocation.BoundParameters
    Write-Host "Entered scope $($Invocation.MyCommand.Name) with parameters [$($Params.Keys) = $($Params.Values)]" -ForegroundColor Blue
}

function Exit-Scope([System.Management.Automation.InvocationInfo]$Invocation) {
    Write-Host "Exited scope $($Invocation.MyCommand.Name)" -ForegroundColor Blue
}

#endregion - Scope Functions

#region - Logging Functions

function Log-AppendFile([Parameter(Mandatory)][String]$Level, [Parameter(Mandatory)][String]$Message) {
    $Path = "$env:temp\DNS_Filter_Checks_Install.log"
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType File -Force | Out-Null
    }

    $Message = "[$Level|$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")]: $Message"
    $Message | Out-File -FilePath $Path -Append
}

function Log-Info([Parameter(Mandatory)][String]$Message) {
    Write-Host $Message -ForegroundColor Green
    Log-AppendFile "INFO" $Message
}

function Log-Warning([Parameter(Mandatory)][String]$Message) {
    Write-Host $Message -ForegroundColor Yellow
    Log-AppendFile "WARNING" $Message
}

function Log-Error([Parameter(Mandatory)][String]$Message) {
    Write-Host $Message -ForegroundColor Red
    Log-AppendFile "ERROR" $Message
}

#endregion - Logging Functions

#region - Install and Uninstall Functions

# TODO - OS detection
function Install-DnsFilterAgent {
    begin { Enter-Scope $MyInvocation }

    process {
        try {
            $Uri = "https://download.dnsfilter.com/User_Agent/Windows/DNS_Agent_Setup.msi"
            $Destination = "$env:windir\Temp\DNS_Agent_Setup.msi"

            Log-Info "Downloading $Uri to $Destination"
            Invoke-WebRequest -Uri $Uri -OutFile $Destination -ErrorAction Stop
        } catch {
            Log-Error "Failed to download $Uri to $Destination"
            return [Result]::Err($_, 999)
        }

        try {
            Log-Info "Attempting to install from [$Destination]"
            $MsiExecDNS = Start-Process msiexec -PassThru -Wait -ArgumentList "/qn", "/i", $Destination, "NKEY=$SiteKey"
            $InstallResult = $MsiExecDNS.ExitCode
            Log-Info "Install result: $InstallResult"

            if ($InstallResult -ne 0) {
                Log-Error "Failed to install from [$Destination] due to error code [$InstallResult]"
                return [Result]::Err($null, $InstallResult)
            }
        } catch {
            Log-Error "Failed to install from [$Destination]"
            return [Result]::Err($_, 888)
        }

        return [Result]::Ok("Installed")
    }

    end { Exit-Scope $MyInvocation }
}

function Uninstall-DnsFilterAgent {
    begin { Enter-Scope $MyInvocation }

    process {
        try {
            Log-Info "Attempting to uninstall DNS Filter"
            Get-Package -Name "DNS Agent" | Uninstall-Package -Force -ErrorAction Stop | Out-Null
        } catch {
            Log-Error "Failed to uninstall DNS Filter"
            return [Result]::Err($_, 888)
        }

        return [Result]::Ok("Uninstalled")
    }

    end { Exit-Scope $MyInvocation }
}

function Get-AgentStatus {
    begin { Enter-Scope $MyInvocation }

    process {
        if ((Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*).DisplayName -contains "DNS Agent") {
            Log-Info "Application is installed"
        } else {
            Log-Info "DNS Filter not installed"
            return [Result]::Err($null, 777)
        }

        if ((Get-Service -Name "DNS Agent").Status -eq "Running") {
            Log-Info "Service is running"
        } else {
            Log-Error "DNS Filter installed but Service is not running"
            return [Result]::Err($null, 666)
        }

        $RegKey = "HKLM:\SOFTWARE\DNSAgent\Agent"
        $RegValue = "NetworkKey"
        $NetworkKey = (Get-ItemProperty -Path $RegKey -Name $RegValue).$RegValue
        if ($NetworkKey -eq $SiteKey) {
            Log-Info "SiteKey is correct"
        } else {
            Log-Error "SiteKey is incorrect"
            return [Result]::Err($null, 1639)
        }

        return [Result]::Ok("Success")

        # TODO: Look into using the API to check the status of this machine with the dashboard
        # FIXME: This needs a permanent API key, currently only able to figure out a jwt token
        # $Uri = https://api.dnsfilter.com/v1/user_agents?search=$env:COMPUTERNAME&type=agents
        # $DashboardStatus = Invoke-WebRequest -Uri $Uri -Headers @{"accept"="application/json"} -ErrorAction Stop
    }

    end { Exit-Scope $MyInvocation }
}

function Main {
    switch ($Action) {
        "Install" {
            if ($null -eq $SiteKey) {
                Log-Error "SiteKey is required for installation."
                exit 1
            }

            $CurrentStatus = Get-AgentStatus
            if ($CurrentStatus.is_ok()) {
                Log-Info "DNS Filter is already installed."
                exit 0
            }

            if ($CurrentStatus.is_err() -and $CurrentStatus.Code -eq 1639) {
                Log-Info "Uninstalling DNS Filter due to mismatching SiteKey."
                $UninstallResult = Uninstall-DnsFilterAgent

                if ($UninstallResult.is_ok()) {
                    Log-Info "DNS Filter uninstalled successfully."
                } else {
                    Log-Error "DNS Filter uninstallation failed."
                    if ($UninstallResult.Err) { Log-Error "Error: $($UninstallResult.Err)" }
                    exit $UninstallResult.Code
                }
            } elseif ($CurrentStatus.is_err() -and $CurrentStatus.Code -ne 777) {
                exit $CurrentStatus.Code
            }

            $InstallResult = Install-DnsFilterAgent
            if ($InstallResult.is_ok()) {
                Log-Info "DNS Filter installed successfully."
            } else {
                Log-Error "DNS Filter installation failed."
                if ($InstallResult.Err) { Log-Error "Error: $($InstallResult.Err)" }

                switch ($InstallResult.Code) {
                    999 { Log-Error "Failed to download installer." }
                    888 { Log-Error "Failed to install." }
                    1639 { Log-Error "Missing or Invalid SiteKey." }
                    default { Log-Error "Unknown error code: $($InstallResult.Code)" }
                }

                exit $InstallResult.Code
            }

            # Due to an issue with the installation, we may have to manually start the service again.
            Start-Sleep 5

            $CurrentStatus = Get-AgentStatus
            if ($CurrentStatus.is_ok()) {
                Log-Info "DNS Filter has installed and is running successfully."
            } elseif (Start-Service -Name "DNS Agent" -ErrorAction SilentlyContinue) {
                Log-Info "DNS Filter encountered an issue on first start, but was able to be recovered."
            } else {
                Log-Error "DNS Filter installation completed without error but the agent is not running."
                exit $CurrentStatus.Code
            }
        }
        "Check" {
            $CurrentStatus = Get-AgentStatus
            if ($CurrentStatus.is_ok()) {
                Log-Info "DNS Filter is installed and running."
                exit 0
            } else {
                Log-Error "DNS Filter is not installed or is not running."
                if ($CurrentStatus.Err) { Log-Error "Error: $($CurrentStatus.Err)" }
                exit $CurrentStatus.Code
            }
        }
        default {
            Log-Error "Invalid action: $Action"
            exit 1
        }
    }
}

Main
