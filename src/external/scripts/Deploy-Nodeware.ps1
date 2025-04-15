#!ignore {"Hash":"33efd32f2e789eb049f02a03631054ff","Patches":["./patches/Deploy-Nodeware_parameters.patch"]}
param(
    [Parameter(Mandatory)]
    $customerID
)

$url = "https://downloads.nodeware.com/agent/windows/NodewareAgentSetup.msi"
$msiName = "NodewareAgentSetup.msi"
$tempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "NodewareInstallTemp")
$msiPath = [System.IO.Path]::Combine($tempDir, $msiName)

try {
    if (-not (Test-Path -Path $tempDir -PathType Container)) {
        New-Item -Path $tempDir -ItemType Directory | Out-Null
    }
    Invoke-WebRequest -Uri $url -OutFile $msiPath

    if (Test-Path -Path $msiPath -PathType Leaf) {
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $msiPath /q CUSTOMERID=$customerID" -Wait
    } else {
        Write-Error "Failed to download the NodewareAgentSetup MSI."
    }
} catch {
    Write-Error "An error occurred: $_"
} finally {
    # Clean up the temp directory and MSI file
    Remove-Item -Path $msiPath -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $tempDir -Force -Recurse -ErrorAction SilentlyContinue
}