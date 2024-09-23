Using module ..\..\common\Environment.psm1
Using module ..\..\common\Logging.psm1
Using module ..\..\common\Exit.psm1

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

Function Invoke-UpdateScript {
    param(
        [String]$BaseUrl,
        [String]$ScriptName
    )

    Invoke-Info "Checking updates for '$File'...";

    [String]$Private:S3ObjectUrl = "$BaseUrl/$ScriptName";

    # TODO - Fix hash check
    # try {
    #     Invoke-Verbose "Fetching HEAD from '$S3ObjectUrl'...";
    #     $null = Invoke-RestMethod -Uri $Private:S3ObjectUrl -Method Head -ResponseHeadersVariable ResponseHeaders;
    # } catch {
    #     Invoke-Error -Message "Failed to fetch HEAD from '$S3ObjectUrl': $($_.Exception.Message)";
    #     Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
    # }

    # [String]$Private:ETag = $ResponseHeaders['ETag'].Trim('"').ToUpper();
    # [String]$Private:LocalFilePath = Join-Path -Path $PSScriptRoot -ChildPath $ScriptName;

    # if (Test-Path $Private:LocalFilePath) {
    #     # Split string into lines, skip first line, recontruct string
    #     [String]$Private:FileContent = Get-Content -Path $Private:LocalFilePath -Raw;
    #     [String[]]$Private:SplitContent = $Private:FileContent.Split("`n", 2);
    #     [String]$Private:LocalFileOriginalContent = $Private:SplitContent[1];
    #     [String]$Private:TempFile = [System.IO.Path]::GetTempFileName();
    #     Set-Content -Path $Private:TempFile -Value $Private:LocalFileOriginalContent;

    #     if (Compare-FileHashToS3ETag -Path:$Private:TempFile -ETag:$ETag) {
    #         Invoke-Info "File '$ScriptName' is up-to-date.";
    #         return;
    #     }
    # }

    Invoke-Info "Fetching '$ScriptName' from '$S3ObjectUrl'...";
    try {
        $Content = Invoke-RestMethod -Uri $S3ObjectUrl;
    } catch {
        Invoke-Error -Message "Failed to fetch '$S3ObjectUrl': $($_.Exception.Message)";
        Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
    }

    try {
        $Content = "#@ignore`n$Content";
        Set-Content -Path $Private:LocalFilePath -Value $Content;
    } catch {
        Invoke-Error -Message "Failed to write '$ScriptName' to '$Private:LocalFilePath': $($_.Exception.Message)";
        Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
    }

    Invoke-Info "File '$ScriptName' has been updated.";
}

Invoke-RunMain $PSCmdlet {
    foreach ($File in $FilesToFetch) {
        Invoke-UpdateScript -BaseUrl:$BaseUrl -ScriptName:$File;
    }
};
