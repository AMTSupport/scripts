[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [String[]]$ApplicationName
)

Import-Module $PSScriptRoot/../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    $Local:Applications = Get-WmiObject -Class Win32_Product | Select-Object -Property Name,Version;
    $Local:LikeApplications = $Local:Applications | Where-Object {
        $Application = $_;
        ($ApplicationName | Where-Object { $Application.Name -like $_; }).Count -gt 0;
    };

    if ($null -eq $Local:LikeApplications) {
        Invoke-Info "No applications found matching '$ApplicationName'";
        return;
    }

    $Local:LikeApplications | ForEach-Object {
        if ($PSCmdlet.ShouldProcess($_.Name, "Uninstall, with version $($_.Version)")) {
            Invoke-Info "Uninstalling $($_.Name) version $($_.Version)";
            wmic product where "Name='$($_.Name)'" call uninstall /nointeractive;
        }
    };
};
