$Script:NOT_ADMINISTRATOR = Register-ExitCode -Description 'Not running as administrator.';
function Invoke-EnsureAdministrator {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Invoke-Error 'Not running as administrator!  Please re-run your terminal session as Administrator, and try again.'
        Invoke-FailedExit -ExitCode $Script:NOT_ADMINISTRATOR;
    }

    Invoke-Verbose -Message 'Running as administrator.';
}

$Script:NOT_USER = Register-ExitCode -Description 'Not running as user.';
function Invoke-EnsureUser {
    if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Invoke-Error 'Not running as user!  Please re-run your terminal session as your normal User, and try again.'
        Invoke-FailedExit -ExitCode $Script:NOT_USER;
    }

    Invoke-Verbose -Message 'Running as user.';
}

$Script:UNABLE_TO_INSTALL_MODULE = Register-ExitCode -Description 'Unable to install module.';
$Script:MODULE_NOT_INSTALLED = Register-ExitCode -Description 'Module not installed and no-install is set.';
$Script:ImportedModules = [System.Collections.Generic.List[String]]::new();
function Invoke-EnsureModules {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String[]]$Modules,

        [Parameter(HelpMessage = 'Do not install the module if it is not installed.')]
        [switch]$NoInstall
    )

    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        foreach ($Local:Module in $Modules) {
            if (Test-Path -Path $Local:Module) {
                Invoke-Debug "Module '$Local:Module' is a local path to a module, importing...";
                $Script:ImportedModules.Add(($Local:Module | Split-Path -LeafBase));
            } elseif (-not (Get-Module -ListAvailable -Name $Local:Module)) {
                if ($NoInstall) {
                    Invoke-Error -Message "Module '$Local:Module' is not installed, and no-install is set.";
                    Invoke-FailedExit -ExitCode $Script:MODULE_NOT_INSTALLED;
                }

                Invoke-Info "Module '$Local:Module' is not installed, installing...";
                try {
                    Install-Module -Name $Local:Module -AllowClobber -Scope CurrentUser -Force;
                    $Script:ImportedModules.Add($Local:Module);
                } catch {
                    Invoke-Error -Message "Unable to install module '$Local:Module'.";
                    Invoke-FailedExit -ExitCode $Script:UNABLE_TO_INSTALL_MODULE;
                }
            } else {
                Invoke-Debug "Module '$Local:Module' is installed.";
                $Script:ImportedModules.Add($Local:Module);
            }

            Invoke-Debug "Importing module '$Local:Module'...";
            Import-Module -Name $Local:Module -Global;
        }

        Invoke-Verbose -Message 'All modules are installed.';
    }
}

$Private:UNABLE_TO_SETUP_NETWORK = Register-ExitCode -Description 'Unable to setup network.';
$Private:NETWORK_NOT_SETUP = Register-ExitCode -Description 'Network not setup, and no details provided.';
function Invoke-EnsureNetwork(
    [Parameter(HelpMessage = 'The name of the network to connect to.')]
    [String]$Name,

    [Parameter(HelpMessage = 'The password of the network to connect if required.')]
    [SecureString]$Password
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        [Boolean]$Local:HasNetwork = (Get-NetConnectionProfile | Where-Object {
            $Local:HasIPv4 = $_.IPv4Connectivity -eq 'Internet';
            $Local:HasIPv6 = $_.IPv6Connectivity -eq 'Internet';

            $Local:HasIPv4 -or $Local:HasIPv6
        } | Measure-Object | Select-Object -ExpandProperty Count) -gt 0;

        if ($Local:HasNetwork) {
            Invoke-Debug 'Network is setup, skipping network setup...';
            return
        }

        if (-not $Name) {
            Invoke-QuickExit -ExitCode $Script:NETWORK_NOT_SETUP;
        }

        Invoke-Info 'Network is not setup, setting up network...';

        [String]$Local:ProfileFile = "$env:TEMP\SetupWireless-profile.xml";
        If ($Local:ProfileFile | Test-Path) {
            Write-Host 'Profile file exists, removing it...';
            Remove-Item -Path $Local:ProfileFile -Force;
        }

        $Local:SSIDHEX = ($Name.ToCharArray() | ForEach-Object { '{0:X}' -f ([int]$_) }) -join ''
        $Local:XmlContent = "<?xml version=""1.0""?>
<WLANProfile xmlns=""http://www.microsoft.com/networking/WLAN/profile/v1"">
    <name>$Name</name>
    <SSIDConfig>
        <SSID>
            <hex>$Local:SSIDHEX</hex>
            <name>$Name</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$NetworkPassword</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"
    }
}

Register-ExitHandler -Name 'Remove Imported Modules' -ExitHandler {
    Invoke-Verbose -Prefix '♻️' -Message "Cleaning up $($Script:ImportedModules.Count) imported modules.";
    Invoke-Verbose -Prefix '✅' -Message "Removing modules: `n`t$($Script:ImportedModules -join "`n`t")";

    Remove-Module -Name $Script:ImportedModules -Force;
};

Export-ModuleMember -Function Invoke-EnsureAdministrator, Invoke-EnsureUser, Invoke-EnsureModules, Invoke-EnsureNetwork;
