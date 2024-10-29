Using module ..\..\common\Environment.psm1
Using module ..\..\common\Logging.psm1
Using module ..\..\common\Scope.psm1

[CmdletBinding(SupportsShouldProcess)]
Param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$URL,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$ExtractTo
)

function Get-DownloadedItem(
    [Parameter(Mandatory)]
    [String]$URL
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -ReturnValue $OutFile; }

    process {
        [String]$OutFolder = [System.IO.Path]::GetTempPath();
        $Request = Invoke-WebRequest -Uri $URL -UseBasicParsing -Method Head;

        if ($Request.StatusCode -ne 200) {
            throw "Failed to download $URL. Status code: $($Request.StatusCode)";
        }

        if ($Request.Headers['Content-Disposition']) {
            $FileName = $Request.Headers['Content-Disposition'] -replace '.*filename="(.*)".*', '$1';
        } else {
            $FileName = [System.IO.Path]::GetFileName($URL);
        }

        $OutFile = [System.IO.Path]::Combine($OutFolder, $FileName);
        Invoke-Info "Downloading $URL to $OutFile";
        Invoke-WebRequest -Uri $URL -OutFile $OutFile;

        return $OutFile;
    }
}

Invoke-RunMain $PSCmdlet {
    if (-not (Test-Path $ExtractTo)) {
        Invoke-Error "ExtractTo path $ExtractTo does not exist.";
        return;
    }

    $Local:DownloadedItem = Get-DownloadedItem -URL $URL;
    # Test if the downloaded item is a zip file, if so extract to the specified location, otherwise move the file to the specified location.
    if ($Local:DownloadedItem -like '*.zip') {
        Invoke-Info "Extracting $Local:DownloadedItem to $ExtractTo";
        Expand-Archive -Path $Local:DownloadedItem -DestinationPath $ExtractTo -Force;
    } else {
        Move-Item -Path $Local:DownloadedItem -Destination $ExtractTo;
    }
};
