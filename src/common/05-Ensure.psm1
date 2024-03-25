$Script:NOT_ADMINISTRATOR = Register-ExitCode -Description "Not running as administrator!`nPlease re-run your terminal session as Administrator, and try again.";
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

$Script:UNABLE_TO_INSTALL_MODULE = Register-ExitCode -Description 'Unable to install module.';
$Script:MODULE_NOT_INSTALLED = Register-ExitCode -Description 'Module not installed and no-install is set.';
$Script:UNABLE_TO_FIND_MODULE = Register-ExitCode -Description 'Unable to find module.';
$Script:ImportedModules = [System.Collections.Generic.List[String]]::new();
function Invoke-EnsureModule {
    <#
    .SYNOPSIS
        Ensures the required modules are installed.

    .DESCRIPTION
        This function will ensure the required modules are installed.
        If the module is not installed, it will be installed.

    .PARAMETER Modules
        The modules represented with their name as a string,
        a git repository string in the format of 'owner/repo@ref', where ref is the branch or tag to install,
        or a hashtable in the following format where items marked with * are optional:
        ```
        @{
            Name = 'ModuleName';
            *MinimumVersion = '1.0.0';
            *DontRemove = $true;
        }
        ```

        These formats can be mixed within the same call, and the module will be installed accordingly.

    .PARAMETER NoInstall
        Do not install the module if it is not installed.

    .EXAMPLE
        Install the ImportExcel and PSScriptAnalyzer modules.
        ```
        Invoke-EnsureModule -Modules 'ImportExcel', 'PSScriptAnalyzer'
        ```
    .EXAMPLE
        Install the ImportExcel module with a minimum version of 7.1.0.
        ```
        Invoke-EnsureModule -Modules @{
            Name = 'ImportExcel';
            MinimumVersion = '7.1.0';
        }
        ```
    .EXAMPLE
        Install the PSReadLine module and don't remove it once the script has completed running.
        ```
        Invoke-EnsureModule -Modules @{
            Name = 'PSReadLine';
            MinimumVersion = '3.2.0';
            DontRemove = $true;
        }
        ```
    .EXAMPLE
        Install the ImportExcel module using the string format, and the PSScriptAnalyzer module using the hashtable format.
        ```
        Invoke-EnsureModule -Modules 'ImportExcel', @{
            Name = 'PSScriptAnalyzer';
            MinimumVersion = '1.0.0';
        }
        ```
    .OUTPUTS
        None
    .EXTERNALHELP
        https://amtsupport.github.io/scripts/docs/modules/common/Ensure/Invoke-EnsureModule
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            $Local:NotValid = $_ | Where-Object {
                $Local:IsString = $_ -is [String];
                $Local:IsHashTable = $_ -is [HashTable] -and $_.Keys.Contains('Name');

                -not ($Local:IsString -or $Local:IsHashTable);
            };

            $Local:NotValid.Count -eq 0;
        })]
        [Object[]]$Modules,

        [Parameter(HelpMessage = 'Do not install the module if it is not installed.')]
        [switch]$NoInstall
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        try {
            $ErrorActionPreference = 'Stop';

            Get-PackageProvider -ListAvailable -Name NuGet | Out-Null;
        } catch {
            try {
                Install-PackageProvider -Name NuGet -ForceBootstrap -Force -Confirm:$False;
                Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted;
            } catch {
                # TODO :: Handle this better, this is a no network case.
                Invoke-Warn 'Unable to install the NuGet package provider, some modules may not be installed.';
                return;
            }
        }

        foreach ($Local:Module in $Modules) {
            $Local:InstallArgs = @{
                AllowClobber = $true;
                Scope = 'CurrentUser';
                Force = $true;
            };

            if ($Local:Module -is [HashTable]) {
                [String]$Local:ModuleName = $Local:Module.Name;

                [String]$Local:ModuleMinimumVersion = $Local:Module.MinimumVersion;
                [Boolean]$Local:DontRemove = $Local:Module.DontRemove;

                if ($Local:ModuleMinimumVersion) {
                    $Local:InstallArgs.Add('MinimumVersion', $Local:ModuleMinimumVersion);
                }
            } else {
                [String]$Local:ModuleName = $Local:Module;
            }

            $Local:InstallArgs.Add('Name', $Local:ModuleName);

            if (Test-Path -Path $Local:ModuleName) {
                Invoke-Debug "Module '$Local:ModuleName' is a local path to a module, importing...";
                if (-not $Local:DontRemove) {
                    $Script:ImportedModules.Add(($Local:ModuleName | Split-Path -LeafBase));
                }
            }

            $Local:AvailableModule = Get-Module -ListAvailable -Name $Local:ModuleName -ErrorAction SilentlyContinue | Select-Object -First 1;
            if ($Local:AvailableModule) {
                Invoke-Debug "Module '$Local:ModuleName' is installed, with version $($Local:AvailableModule.Version).";

                if ($Local:ModuleMinimumVersion -and $Local:AvailableModule.Version -lt $Local:ModuleMinimumVersion) {
                    Invoke-Verbose 'Module is installed, but the version is less than the minimum version required, trying to update...';
                    try {
                        Install-Module @Local:InstallArgs | Out-Null;
                    } catch {
                        Invoke-Error -Message "Unable to update module '$Local:ModuleName'.";
                        Invoke-FailedExit -ExitCode $Script:UNABLE_TO_INSTALL_MODULE;
                    }
                }

                if (-not $Local:DontRemove) {
                    $Script:ImportedModules.Add($Local:ModuleName);
                }
            } else {
                if ($NoInstall) {
                    Invoke-Error -Message "Module '$Local:ModuleName' is not installed, and no-install is set.";
                    Invoke-FailedExit -ExitCode $Script:MODULE_NOT_INSTALLED;
                }

                if (Find-Module -Name $Local:ModuleName -ErrorAction SilentlyContinue) {
                    Invoke-Info "Module '$Local:ModuleName' is not installed, installing...";
                    try {
                        Install-Module @Local:InstallArgs;

                        if (-not $Local:DontRemove) {
                            $Script:ImportedModules.Add($Local:ModuleName);
                        }
                    } catch {
                        Invoke-Error -Message "Unable to install module '$Local:ModuleName'.";
                        Invoke-FailedExit -ExitCode $Script:UNABLE_TO_INSTALL_MODULE;
                    }
                } elseif ($Local:ModuleName -match '^(?<owner>.+?)/(?<repo>.+?)(?:@(?<ref>.+))?$') {
                    # Try to install the module from a git repository.
                    # Parse the input string into <owner>/<repo>/<ref>
                    [String]$Local:Owner = $Matches.owner;
                    [String]$Local:Repo = $Matches.repo;
                    [String]$Local:Ref = $Matches.ref;
                    [String]$Local:ProjectUri = "https://github.com/$Local:Owner/$Local:Repo";

                    Invoke-Info "Module '$Local:ModuleName' not found in PSGallery, trying to install from git...";
                    Invoke-Debug "$Local:ProjectUri, $Local:Ref";

                    try {
                        [String]$Local:ModuleName = Install-ModuleFromGitHub -GitHubRepo "$Local:Owner/$Local:Repo" -Branch $Local:Ref -Scope CurrentUser;

                        if (-not $Local:DontRemove) {
                            $Script:ImportedModules.Add($Local:ModuleName);
                        }
                    } catch {
                        Invoke-Error -Message "Unable to install module '$Local:ModuleName' from git.";
                        Invoke-FailedExit -ExitCode $Script:UNABLE_TO_INSTALL_MODULE;
                    }
                } else {
                    Invoke-Error -Message "Module '$Local:ModuleName' could not be found using Find-Module, and was not a git repoistory.";
                    Invoke-FailedExit -ExitCode $Script:UNABLE_TO_FIND_MODULE;
                }
            }

            Invoke-Debug "Importing module '$Local:ModuleName'...";
            Import-Module -Name $Local:ModuleName -Global -Force;
        }

        Invoke-Verbose -Message 'All modules are installed.';
    }
}

$Script:WifiXmlTemplate = "<?xml version=""1.0""?>
<WLANProfile xmlns=""http://www.microsoft.com/networking/WLAN/profile/v1"">
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
";
$Private:NO_CONNECTION_AFTER_SETUP = Register-ExitCode -Description 'Failed to connect to the internet after network setup.';
function Invoke-EnsureNetwork(
    [Parameter(HelpMessage = 'The name of the network to connect to.')]
    [ValidateNotNullOrEmpty()]
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

Export-ModuleMember -Function Invoke-EnsureAdministrator, Invoke-EnsureUser, Invoke-EnsureModule, Invoke-EnsureNetwork;
