Using module .\Utils.psm1
Using module .\Logging.psm1
Using module .\Scope.psm1
Using module .\Exit.psm1
Using module .\Temp.psm1

$Script:NOT_ADMINISTRATOR = Register-ExitCode -Description @'
Not running as administrator!
Please re-run your terminal session as Administrator, and try again.
'@;

<#
.SYNOPSIS
    Ensures the current session is running as an Administrator.

.DESCRIPTION
    This function will check if the current session is running as an Administrator.
    If it is not, it will exit with an error code.

.EXAMPLE
    Invoke-EnsureAdministrator

.OUTPUTS
    None
#>
function Invoke-EnsureAdministrator {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Invoke-FailedExit -ExitCode $Script:NOT_ADMINISTRATOR;
    }

    Invoke-Verbose -Message 'Running as administrator.';
}

$Script:NOT_USER = Register-ExitCode -Description "Not running as user!`nPlease re-run your terminal session as your normal User, and try again.";
function Invoke-EnsureUser {
    if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Invoke-FailedExit -ExitCode $Script:NOT_USER;
    }

    Invoke-Verbose -Message 'Running as user.';
}

$Script:WifiXmlTemplate = '<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>{0}</name>
  <SSIDConfig>
    <SSID>
      <hex>{1}</hex>
      <name>{0}</name>
    </SSID>
  </SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>auto</connectionMode>
  <MSM>
    <security>
      <authEncryption>
        <authentication>{2}</authentication>
        <encryption>{3}</encryption>
        <useOneX>false</useOneX>
      </authEncryption>
      <sharedKey>
        <keyType>passPhrase</keyType>
        <protected>false</protected>
        <keyMaterial>{4}</keyMaterial>
      </sharedKey>
    </security>
  </MSM>
</WLANProfile>
';
$Private:NO_CONNECTION_AFTER_SETUP = Register-ExitCode -Description 'Failed to connect to the internet after network setup.';
function Invoke-EnsureNetwork(
    [Parameter(HelpMessage = 'The name of the network to connect to.')]
    [ValidateNotNullOrEmpty()]
    [String]$Name,

    [Parameter(HelpMessage = 'The password of the network to connect if required.')]
    [SecureString]$Password
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope; }

    process {
        [Boolean]$Local:HasNetwork = (Get-NetConnectionProfile | Where-Object {
                $Local:HasIPv4 = $_.IPv4Connectivity -eq 'Internet';
                $Local:HasIPv6 = $_.IPv6Connectivity -eq 'Internet';

                $Local:HasIPv4 -or $Local:HasIPv6
            } | Measure-Object | Select-Object -ExpandProperty Count) -gt 0;

        if ($Local:HasNetwork) {
            Invoke-Debug 'Network is setup, skipping network setup...';
            return $false;
        }

        Invoke-Info 'Network is not setup, setting up network...';

        Invoke-WithinEphemeral {
            [String]$Local:ProfileFile = "$Name.xml";
            [String]$Local:SSIDHex = ($Name.ToCharArray() | ForEach-Object { '{0:X}' -f ([int]$_) }) -join '';
            if ($Password) {
                $Local:SecureBSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password);
                $Local:PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($Local:SecureBSTR);
            }

            [Xml]$Local:XmlContent = [String]::Format($Script:WifiXmlTemplate, $Name, $SSIDHex, 'WPA2PSK', 'AES', $PlainPassword);
            # Remove the password if it is not provided.
            if (-not $PlainPassword) {
                $Local:XmlContent.WLANProfile.MSM.security.RemoveChild($Local:XmlContent.WLANProfile.MSM.security.sharedKey) | Out-Null;
            }

            $Local:XmlContent.InnerXml | Out-File -FilePath $Local:ProfileFile -Encoding UTF8;

            if ($WhatIfPreference) {
                Invoke-Info -Message 'WhatIf is set, skipping network setup...';
                return $true;
            } else {
                Invoke-Info -Message 'Setting up network...';
                netsh wlan add profile filename="$Local:ProfileFile" | Out-Null;
                netsh wlan show profiles $Name key=clear | Out-Null;
                netsh wlan connect name="$Name" | Out-Null;

                Invoke-Info 'Waiting for network connection...'
                $Local:RetryCount = 0;
                while (-not (Test-Connection -Destination google.com -Count 1 -Quiet)) {
                    If ($Local:RetryCount -ge 60) {
                        Invoke-Error "Failed to connect to $NetworkName after 10 retries";
                        Invoke-FailedExit -ExitCode $Private:NO_CONNECTION_AFTER_SETUP;
                    }

                    Start-Sleep -Seconds 1
                    $Local:RetryCount += 1
                }

                Invoke-Info -Message 'Network setup successfully.';
                return $True;
            }
        }
    }
}

Register-ExitHandler -Name 'Remove Imported Modules' -ExitHandler {
    if ($Script:ImportedModules.Count -lt 1) {
        Invoke-Debug 'No additional modules were imported, skipping cleanup...';
        return;
    }

    Invoke-Verbose -Prefix '♻️' -Message "Cleaning up $($Script:ImportedModules.Count) additional imported modules.";
    Invoke-Verbose -Prefix '✅' -Message "Removed modules: `n`t$($Script:ImportedModules -join "`n`t")";

    Remove-Module -Name $Script:ImportedModules -Force;
};

Export-ModuleMember -Function Invoke-EnsureAdministrator, Invoke-EnsureUser, Invoke-EnsureNetwork;
