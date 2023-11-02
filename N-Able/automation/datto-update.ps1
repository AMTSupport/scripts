#region - Scope Functions

function Enter-Scope([System.Management.Automation.InvocationInfo]$Invocation) {
    $Params = $Invocation.BoundParameters
    Write-Host "Entered scope $($Invocation.MyCommand.Name) with parameters [$($Params.Keys) = $($Params.Values)]"
}

function Exit-Scope([System.Management.Automation.InvocationInfo]$Invocation) {
    Write-Host "Exited scope $($Invocation.MyCommand.Name)"
}

#endregion - Scope Functions

#region - Script Functions

function Get-Installer([String]$Version) {
    begin { Enter-Scope $MyInvocation }

    process {
        if ($null -eq $Version) {
            Write-Error "Version cannot be null"
        }

        Write-Host "Getting installer for version [$Version]"

        [String]$InstallerURL = "https://us.workplace.datto.com/update/DattoWorkplaceSetup_v${Version}.exe";
        [String]$InstallerPath = "${env:TEMP}/DattoWorkplaceSetup_v${Version}.exe";

        if (-not (Test-Path $InstallerPath)) {
            Write-Host "Downloading installer from [$InstallerURL] to [$InstallerPath]"
            Invoke-WebRequest -Uri $InstallerURL -OutFile $InstallerPath -UseBasicParsing
        }

        return $InstallerPath
    }

    end { Exit-Scope $MyInvocation }
}

function Get-InstalledVersion {
    begin { Enter-Scope $MyInvocation }

    process {
        [String]$RegistryPath = "HKLM:\SOFTWARE\Datto\Workplace CloudConnect";
        [String]$RegistryProperty = "DriverUpdate";

        if (-not (Test-Path $RegistryPath)) {
            Write-Error "Registry path [$RegistryPath] does not exist"
        }

        [String]$Version = (Get-ItemProperty -Path $RegistryPath -Name $RegistryProperty).$RegistryProperty;

        Write-Host "Found installed version [$Version]"
        return $Version
    }

    end { Exit-Scope $MyInvocation }
}

function Get-UpdateVersion {
    begin { Enter-Scope $MyInvocation }

    process {
        [Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject]$Raw = Invoke-WebRequest -Uri "https://us.workplace.datto.com/download" -UseBasicParsing;
        [String]$Href = ($Raw.Links | Where-Object { $_.href -like "https&#x3a;&#x2f;&#x2f;us&#x2e;workplace&#x2e;datto&#x2e;com&#x2f;update&#x2f;DattoWorkplaceSetup*" } | Select-Object -Property href).href;

        Write-Debug "Found href [$Href]"

        if ($null -eq $Href) {
            Write-Error "Could not find update version";
        }

        [String]$Decoded = [System.Net.WebUtility]::HtmlDecode($Href);
        [String]$Version = $Decoded -replace "https://us.workplace.datto.com/update/DattoWorkplaceSetup_v", "" -replace ".exe", "";

        Write-Host "Found update version [$Version]"
        return $Version
    }

    end { Exit-Scope $MyInvocation }
}

function Install-Update([String]$InstallerPath) {
    begin { Enter-Scope $MyInvocation }

    process {
        if ($null -eq $InstallerPath) {
            Write-Error "Installer path cannot be null"
        }

        if (-not (Test-Path $InstallerPath)) {
            Write-Error "Installer path [$InstallerPath] does not exist"
        }

        Write-Host "Installing update from [$InstallerPath]"

        Start-Process -FilePath $InstallerPath -ArgumentList "/install /quiet /norestart" -Wait
    }

    end { Exit-Scope $MyInvocation }
}

function Main {
    begin { Enter-Scope $MyInvocation }

    process {
        [String]$InstalledVersion = Get-InstalledVersion
        [String]$UpdateVersion = Get-UpdateVersion

        if ($InstalledVersion -eq $UpdateVersion) {
            Write-Host "Installed version [$InstalledVersion] is up to date"
        } else {
            Write-Host "Installed version [$InstalledVersion] is out of date, updating to [$UpdateVersion]"
            [String]$InstallerPath = Get-Installer -Version $UpdateVersion
            Install-Update -InstallerPath $InstallerPath
        }
    }

    end { Exit-Scope $MyInvocation }
}

#endregion - Script Functions

Main
