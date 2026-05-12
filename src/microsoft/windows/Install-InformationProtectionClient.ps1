[CmdletBinding()]
Param()

$url = "https://download.microsoft.com/download/5e62f7f5-d616-49f8-b506-f1c6b4f79ba7/PurviewInfoProtection.msi"
$output = "C:\temp\PurviewInfoProtection.msi"

function Test-InformationProtectionClientInstalled {
    $registryPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    $appNames = @(
        "Microsoft Purview Information Protection",
        "Azure Information Protection",
        "Purview Information Protection"
    )

    foreach ($registryPath in $registryPaths) {
        if (Test-Path $registryPath) {
            $installedApps = Get-ChildItem -Path $registryPath -ErrorAction SilentlyContinue

            foreach ($app in $installedApps) {
                $displayName = $app.GetValue("DisplayName")

                foreach ($appName in $appNames) {
                    if ($displayName -like "*$appName*") {
                        Write-Host "Information Protection Client is already installed: $displayName"
                        return $true
                    }
                }
            }
        }
    }

    return $false
}

if (Test-InformationProtectionClientInstalled) {
    Write-Host "Installation skipped: Information Protection Client is already present on this system."
    exit 0
}

Write-Host "Information Protection Client not detected. Proceeding with installation..."

if (-not (Test-Path "C:\temp")) {
    New-Item -ItemType Directory -Path "C:\temp" -Force | Out-Null
}

Import-Module BitsTransfer
Write-Host "Downloading Information Protection Client..."
Start-BitsTransfer -Source $url -Destination $output

Write-Host "Installing Information Protection Client..."
msiexec.exe /i "$output" /qn

Write-Host "Installation completed."
