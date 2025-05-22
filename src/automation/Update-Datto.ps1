Using module ..\common\Environment.psm1
Using module ..\common\Logging.psm1
Using module ..\common\Scope.psm1

[CmdletBinding(SupportsShouldProcess)]
[OutputType([Void])]
param()

function Get-Installer {
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Version
    )

    begin { Enter-Scope }
    end { Exit-Scope }

    process {
        Invoke-Info "Getting installer for version [$Version]"

        [String]$InstallerURL = "https://us.workplace.datto.com/update/DattoWorkplaceSetup_v${Version}.exe";
        [String]$InstallerPath = "${env:TEMP}/DattoWorkplaceSetup_v${Version}.exe";

        if (Test-Path $InstallerPath) {
            $InstallerLastModified = Get-Item -Path $InstallerPath -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LastWriteTime;
            Invoke-Info "Found installer at [$InstallerPath] with last modified date [$InstallerLastModified]"
            if ($InstallerLastModified -lt (Get-Date).AddDays(-1)) {
                Invoke-Info "Installer is older than 1 day, deleting"
                Remove-Item -Path $InstallerPath -Force | Out-Null;
            }
        }

        if (-not (Test-Path $InstallerPath)) {
            Invoke-Info "Downloading installer from [$InstallerURL] to [$InstallerPath]"
            $Attempt = 0;
            while ($Attempt -lt 5) {
                $Attempt++;
                $Request = Invoke-WebRequest -Uri $InstallerURL -OutFile $InstallerPath -UseBasicParsing -PassThru;
                if ($Request.StatusCode -eq 200) {
                    Invoke-Info "Downloaded installer from [$InstallerURL] to [$InstallerPath]"
                    break;
                } else {
                    if ($Attempt -eq 5) {
                        Invoke-Error "Failed to download installer from [$InstallerURL] after 5 attempts" -Throw;
                    }

                    Invoke-Warn "Failed to download installer from [$InstallerURL], retrying in 5 seconds"
                    Invoke-Debug "Request status code [$($Request.StatusCode)]"
                    Remove-Item -Path $InstallerPath -Force | Out-Null;
                    Start-Sleep -Seconds 5;
                }
            }
        }

        return $InstallerPath
    }
}

function Get-InstalledVersion {
    [CmdletBinding()]
    [OutputType([String])]
    param()

    begin { Enter-Scope }
    end { Exit-Scope }

    process {
        [String]$RegistryPath = "HKLM:\SOFTWARE\Datto\Workplace CloudConnect";
        [String]$RegistryProperty = "DriverUpdate";

        if (-not (Test-Path $RegistryPath)) {
            Invoke-Error "Registry path [$RegistryPath] does not exist" -Throw;
        }

        [String]$Version = (Get-ItemProperty -Path $RegistryPath -Name $RegistryProperty).$RegistryProperty;

        Invoke-Info "Found installed version [$Version]"
        return $Version
    }
}

function Get-UpdateVersion {
    [CmdletBinding()]
    [OutputType([String])]
    param()

    begin { Enter-Scope }
    end { Exit-Scope }

    process {
        [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject]$Raw = Invoke-WebRequest -Uri "https://us.workplace.datto.com/download" -UseBasicParsing;
        [String]$Href = ($Raw.Links | Where-Object { $_.href -like "https&#x3a;&#x2f;&#x2f;us&#x2e;workplace&#x2e;datto&#x2e;com&#x2f;update&#x2f;DattoWorkplaceSetup*" } | Select-Object -Property href).href;

        Write-Debug "Found href [$Href]"

        if ($null -eq $Href) {
            Invoke-Error "Could not find update version" -Throw;
        }

        [String]$Decoded = [System.Net.WebUtility]::HtmlDecode($Href);
        [String]$Version = $Decoded -replace "https://us.workplace.datto.com/update/DattoWorkplaceSetup_v", "" -replace ".exe", "";

        Invoke-Info "Found update version [$Version]"
        return $Version
    }
}

function Install-Update(
    [Parameter(Mandatory, SupportsShouldProcess)]
    [ValidateNotNullOrEmpty()]
    [String]$InstallerPath
) {
    begin { Enter-Scope }
    end { Exit-Scope }

    process {
        if (-not (Test-Path $InstallerPath)) {
            Invoke-Error "Installer path [$InstallerPath] does not exist" -Throw
        }

        Invoke-Info "Installing update from [$InstallerPath]"

        if ($PSCmdlet.ShouldProcess("Install update from [$InstallerPath]", "Simulate Update")) {
            Invoke-Info "Would have run installer with arguments [/install /quiet /norestart /log:${env:TEMP}/DattoUpdateLog.txt]"
        } else {
            $Process = Start-Process -FilePath $InstallerPath -ArgumentList "/install","/quiet","/norestart","/log:${env:TEMP}/DattoUpdateLog.txt" -Wait -PassThru;
            if ($Process.ExitCode -ne 0) {
                Invoke-Error "Failed to install update from [$InstallerPath], exit code [$($Process.ExitCode)]";
                Invoke-Error (Get-Content -Path "${env:TEMP}/DattoUpdateLog.txt") -Throw;
            } else {
                Invoke-Info "Successfully installed update from [$InstallerPath]"
            }
        }
    }
}

Invoke-RunMain $PSCmdlet {
    try {
        $InstalledVersion = Get-InstalledVersion
    } catch {
        if (-not $PSCmdlet.ShouldContinue("Could not get installed version, not updating", "Simulate Update?")) {
            Invoke-Warn 'Could not get installed version, not updating';
            return;
        }
    }

    $UpdateVersion = Get-UpdateVersion

    if ($InstalledVersion -eq $UpdateVersion) {
        Invoke-Info "Installed version [$InstalledVersion] is up to date"
    } else {
        Invoke-Info "Installed version [$InstalledVersion] is out of date, updating to [$UpdateVersion]"
        $InstallerPath = Get-Installer -Version $UpdateVersion
        Install-Update -InstallerPath $InstallerPath
    }
}
