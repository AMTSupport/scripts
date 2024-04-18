[CmdletBinding()]
param(
    [String]$BaseUrl = 'https://s3.amazonaws.com/new-swmsp-net-supportfiles/PermanentFiles/FeatureCleanup/Cleanup Scripts',

    [String[]]$FilesToFetch = @(
        'avdCleanup.ps1',
        'N-sightRMMCleanup.ps1',
        'PMECleanup.ps1',
        'TakeControlCleanup.ps1',
        'WindowsAgentCleanup.ps1'
    )
)

Function Update-Script {
    param(
        [String]$BaseUrl,
        [String]$ScriptName
    )

    Invoke-Info "Checking updates for '$File'...";

    [String]$Private:S3ObjectUrl = "$BaseUrl/$ScriptName";

    try {
        Invoke-Verbose "Fetching HEAD from '$S3ObjectUrl'...";
        $null = Invoke-RestMethod -Uri $Private:S3ObjectUrl -Method Head -ResponseHeadersVariable ResponseHeaders;
    } catch {
        Invoke-Error -Message "Failed to fetch HEAD from '$S3ObjectUrl': $($_.Exception.Message)";
        Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
    }

    [String]$Private:ETag = $ResponseHeaders['ETag'].Trim('"').ToUpper();
    [String]$Private:LocalFilePath = Join-Path -Path $PSScriptRoot -ChildPath $ScriptName;
    if ((Test-Path $Private:LocalFilePath) -and ((Get-FileHash -Path $Private:LocalFilePath -Algorithm MD5).Hash -eq $Private:ETag)) {
        Invoke-Info "File '$ScriptName' is up to date.";
        return;
    }

    Invoke-Info "Fetching '$ScriptName' from '$S3ObjectUrl'...";
    try {
        Invoke-RestMethod -Uri $S3ObjectUrl -OutFile $Private:LocalFilePath;
    } catch {
        Invoke-Error -Message "Failed to fetch '$S3ObjectUrl': $($_.Exception.Message)";
        Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
    }

    Invoke-Info "File '$ScriptName' has been updated.";
}

Import-Module $PSScriptRoot/../../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    foreach ($File in $FilesToFetch) {
        Update-Script -BaseUrl:$BaseUrl -ScriptName:$File;
    }
};
