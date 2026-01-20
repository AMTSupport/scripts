Using module .\Logging.psm1
Using module .\Exit.psm1

$Script:ERROR_INVALID_HEADERS = Register-ExitCode -Description 'Failed to get headers from {0}';
$Script:ERROR_BLOB_HEAD_FAILED = Register-ExitCode -Description 'Failed to get headers from blob {0}';
$Script:ERROR_BLOB_LIST_FAILED = Register-ExitCode -Description 'Failed to list blobs from container {0}';

function ConvertTo-SasQueryString {
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory)]
        [String]$SasToken
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Result; }

    process {
        [Regex]$Private:Regex = [Regex]::new('(?<key>[A-z]+)=(?<value>[A-z\d-:/+=]+)&?');
        $Private:Matches = $Private:Regex.Matches($SasToken);

        $Private:Query = [ordered]@{};
        foreach ($Private:Match in $Private:Matches) {
            $Private:Key = $Private:Match.Groups['key'].Value;
            $Private:RawValue = $Private:Match.Groups['value'].Value;
            $Private:Value = if ($Private:Key -eq 'sig') {
                [URI]::EscapeDataString($Private:RawValue);
            } else {
                $Private:RawValue;
            }

            $Private:Query[$Private:Key] = $Private:Value;
        }

        [String]$Local:Result = ($Private:Query.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value -Replace '\\','')" }) -join '&';
        return $Local:Result;
    }
}

function Get-BlobCompatableHash {
    param(
        [Parameter(Mandatory)]
        [String]$Path
    )

    begin {
        Enter-Scope;
        $Private:Algorithm = [System.Security.Cryptography.HashAlgorithm]::Create('MD5');
    }
    end { Exit-Scope; }

    process {
        [Byte[]]$Private:ByteStream = [System.IO.File]::ReadAllBytes($Path);
        [Byte[]]$Private:HashBytes = $Private:Algorithm.ComputeHash($Private:ByteStream);

        return [System.Convert]::ToBase64String($Private:HashBytes);
    }
}

function Find-FileByHash {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [String]$Hash,

        [Parameter(Mandatory)]
        [Object]$Path,

        [String]$Filter = '*'
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:File.FullName; }

    process {
        if (-not (Test-Path -Path $Path)) {
            return $null;
        }

        Invoke-Info "Looking for file with hash $Hash in $Path...";

        foreach ($Local:File in Get-ChildItem -Path $Path -File -Filter:$Filter) {
            [String]$Local:FileHash = Get-BlobCompatableHash -Path:$Local:File.FullName;
            Invoke-Debug "Checking file $($Local:File.FullName) with hash $Local:FileHash...";
            if ($Local:FileHash -eq $Hash) {
                return $Local:File.FullName;
            }
        }

        return $null;
    }
}

function Get-BlobList {
    [CmdletBinding()]
    [OutputType([String[]])]
    param(
        [Parameter(Mandatory)]
        [String]$ContainerUrl,

        [Parameter(Mandatory)]
        [String]$SasQueryString
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:AllBlobs; }

    process {
        [System.Collections.Generic.List[String]]$Local:AllBlobs = [System.Collections.Generic.List[String]]::new();
        [String]$Local:Marker = '';

        do {
            [String]$Local:ListParams = "restype=container&comp=list&maxresults=500";
            if ($Local:Marker) {
                $Local:ListParams += "&marker=$Local:Marker";
            }

            [String]$Local:Uri = "${ContainerUrl}?${Local:ListParams}&${SasQueryString}";

            Invoke-Debug "Listing blobs from $Local:Uri...";

            try {
                [xml]$Local:Response = Invoke-RestMethod -Uri:$Local:Uri -Method:GET;
            } catch {
                Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:ERROR_BLOB_LIST_FAILED -FormatArgs @($ContainerUrl);
            }

            $Local:Blobs = $Local:Response.EnumerationResults.Blobs.Blob;
            if ($Local:Blobs) {
                foreach ($Local:Blob in $Local:Blobs) {
                    [String]$Local:BlobName = $Local:Blob.Name;
                    [String]$Local:Extension = [System.IO.Path]::GetExtension($Local:BlobName).ToLowerInvariant();

                    if ($Script:SupportedExtensions -contains $Local:Extension) {
                        Invoke-Debug "Found font blob: $Local:BlobName";
                        $Local:AllBlobs.Add($Local:BlobName);
                    }
                }
            }

            $Local:Marker = $Local:Response.EnumerationResults.NextMarker;
        } while ($Local:Marker);

        Invoke-Info "Found $($Local:AllBlobs.Count) font files in container.";
        return $Local:AllBlobs.ToArray();
    }
}

function Get-BlobMD5 {
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory)]
        [String]$BlobUri
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:MD5; }

    process {
        try {
            $Local:ResponseHeaders = Invoke-WebRequest -UseBasicParsing -Uri:$BlobUri -Method:HEAD | Select-Object -ExpandProperty Headers;
            [String]$Local:MD5 = $Local:ResponseHeaders['Content-MD5'];
            return $Local:MD5;
        } catch {
            Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:ERROR_BLOB_HEAD_FAILED -FormatArgs @($BlobUri);
        }
    }
}

function Get-FromBlob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByDirectUrl')]
        [String]$Url,

        [Parameter(Mandatory, ParameterSetName = 'ByUrlAndPath')]
        [String]$BaseURL,

        [Parameter(Mandatory, ParameterSetName = 'ByUrlAndPath')]
        [String]$Path,

        [Parameter(Mandatory)]
        [String]$CachePath,

        [Parameter(Mandatory)]
        [String]$SasToken
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:OutPath; }

    process {
        $Private:UrlParams = ConvertTo-SasQueryString -SasToken $SasToken;

         if ($PSCmdlet.ParameterSetName -eq 'ByDirectUrl') {
            [String]$Local:Uri = "${Url}?${Private:UrlParams}";
        } elseif ($PSCmdlet.ParameterSetName -eq 'ByUrlAndPath') {
            [String]$Local:Uri = "${$BaseURL | Join-Path -ChildPath $Path}?${Private:UrlParams}";
        } else {
            Invoke-FailedExit -Message "Invalid parameter set: $($PSCmdlet.ParameterSetName)";
        }

        [String]$Local:MD5 = Get-BlobMD5 -BlobUri $Local:Uri
        [System.IO.FileInfo]$Local:ExistingFile = Find-FileByHash -Hash:$Local:MD5 -Path:$CachePath -Filter:'*.png';

        if ($Local:ExistingFile) {
            Invoke-Info "Using existing file {$Local:ExistingFile}...";
            return $Local:ExistingFile;
        }

        [String]$Local:OutPath = $CachePath | Join-Path -ChildPath ([System.IO.Path]::GetRandomFileName() + '.png');
        Invoke-RestMethod -Uri:$Local:Uri -Method:GET -OutFile:$Local:OutPath;

        Unblock-File -Path $Local:OutPath;
        return $Local:OutPath;
    }
}

Export-ModuleMember -Function ConvertTo-SasQueryString, Get-BlobCompatableHash, Get-BlobMD5, Get-BlobList, Find-FileByHash, Get-FromBlob
