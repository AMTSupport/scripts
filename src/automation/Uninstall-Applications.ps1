Using module ../common/Environment.psm1
Using module ../common/Logging.psm1
Using module ../common/Utils.psm1
Using module ../common/Analyser.psm1

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [String[]]$ApplicationName
)

# TODO wmic no longer available on Windows 11 need to find alternative.
Invoke-RunMain $PSCmdlet {
    [Compiler.Analyser.SuppressAnalyserAttribute(
        CheckType = 'UseOfUndefinedFunction',
        Data = 'wmic',
        Justification = 'wmic is not available on the builder machine'
    )]
    param()

    if (Test-IsWindows11) {
        Invoke-Error 'This script is currently broken due to wmic not being available on Windows 11';
    }

    $Local:Applications = Get-CimInstance -ClassName Win32_Product | Select-Object -Property Name,Version;
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
