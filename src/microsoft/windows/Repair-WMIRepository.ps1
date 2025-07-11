Using module ..\..\common\Environment.psm1
Using module ..\..\common\Logging.psm1
Using module ..\..\common\Ensure.psm1

[CmdletBinding(SupportsShouldProcess)]
param(
    [Switch]$Nuke
)

function Get-DependentServices {
    param (
        [Parameter(Mandatory)]
        [string]$ServiceName
    )

    $service = Get-Service -Name $ServiceName
    $dependentServices = $service.DependentServices

    $result = @{}
    foreach ($dependentService in $dependentServices) {
        if (!$result.ContainsKey($dependentService.ServiceName)) {
            $Private:Service = Get-Service -Name $dependentService.ServiceName;

            if ($Private:Service.Status -ne 'Running') {
                continue;
            }

            $result[$dependentService.ServiceName] = $Private:Service.StartType;
            if (!$result.ContainsKey($dependentService.ServiceName)) {
                $result += Get-DependentServices -ServiceName $dependentService.ServiceName
            }
        }
    }

    return $result
}

Invoke-RunMain $PSCmdlet {
    Invoke-EnsureAdministrator;

    $Private:Dependants = Get-DependentServices -ServiceName Winmgmt;
    if ($Private:Dependants) {
        Invoke-Info 'The following services are dependent on the WMI service and are currently running:';
        $Private:Dependants.Keys | ForEach-Object {
            Invoke-Info $_;
        }

        $Private:Dependants.Keys | ForEach-Object {
            Invoke-Info "Stopping $_";
            Set-Service -Name $_ -StartupType Disabled;
            Stop-Service -Name $_;
        }
    }

    Invoke-Info 'Stopping WMI service';
    Set-Service -Name Winmgmt -StartupType Disabled;
    Stop-Service -Name Winmgmt;

    if ($Cmdlet.ShouldProcess('WMI Repository', 'Backup')) {
        Invoke-Info 'Making a backup of the repository';
        Copy-Item -Path $env:windir\System32\wbem\Repository -Destination $env:windir\System32\wbem\Repository_Backup -Recurse -Force;
    }

    if ($Nuke) {
        if ($Cmdlet.ShouldProcess('WMI Repository', 'Nuke')) {
            Invoke-Info 'Nuking the WMI repository';
            try {
                Remove-Item -Path $env:windir\System32\wbem\Repository -Recurse -Force;
            } catch {
                Invoke-Error $_.Exception.Message;
            }
        }
    } else {
        if ($Cmdlet.ShouldProcess('WMI Repository', 'Repair')) {
            Invoke-Info 'Attempting to repair the WMI repository';
            try {
                Start-Process -FilePath "$env:windir\System32\wbem\winmgmt.exe" -ArgumentList "/salvagerepository $env:windir\System32\wbem" -Wait -NoNewWindow;
                Start-Process -FilePath "$env:windir\System32\wbem\winmgmt.exe" -ArgumentList "/resetrepository $env:windir\System32\wbem" -Wait -NoNewWindow;
            } catch {
                Invoke-Error $_.Exception.Message;
            }
        }
    }

    Invoke-Info 'Starting WMI service';
    Set-Service -Name Winmgmt -StartupType Automatic;
    Start-Service -Name Winmgmt;

    if ($Private:Dependants) {
        Invoke-Info 'Starting dependent services';
        $Private:Dependants.Keys | ForEach-Object {
            Invoke-Info "Starting $_";
            Set-Service -Name $_ -StartupType $Private:Dependants[$_];
            try {
                Start-Service -Name $_;
            } catch {
                Invoke-Error "Error while restarting $($_): $($_.Exception.Message)";
                continue;
            }
        }
    }

    Invoke-Info 'You should restart the computer to ensure that everything works correctly.';
};
