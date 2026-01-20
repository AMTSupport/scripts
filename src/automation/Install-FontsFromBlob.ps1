Using module ..\common\Environment.psm1
Using module ..\common\Logging.psm1
Using module ..\common\Utils.psm1
Using module ..\common\Scope.psm1
Using module ..\common\Registry.psm1
Using module ..\common\Ensure.psm1
Using module ..\common\Exit.psm1
Using module ..\common\Blob.psm1

<#
.SYNOPSIS
    Downloads and installs fonts from an Azure Blob Storage container.

.DESCRIPTION
    Lists all font files (.ttf, .otf, .ttc) in a specified Azure Blob container,
    downloads them if not already cached locally (using MD5 hash comparison),
    and installs any fonts that are not already installed system-wide.

.PARAMETER StorageBlobUrl
    The URL to the Azure Blob Storage container (e.g., https://account.blob.core.windows.net/fonts).

.PARAMETER StorageBlobSasToken
    The SAS token for accessing the blob container.

.EXAMPLE
    .\Install-FontsFromBlob.ps1 -StorageBlobUrl 'https://myaccount.blob.core.windows.net/fonts' -StorageBlobSasToken 'sv=2021-06-08&ss=b&srt=co&sp=rl&se=...'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$StorageBlobUrl,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$StorageBlobSasToken
)

[String]$Script:FontCacheFolder = $env:ProgramData | Join-Path -ChildPath 'AMT' | Join-Path -ChildPath 'Fonts' | Join-Path -ChildPath 'Cache';
[String]$Script:FontsFolder = $env:windir | Join-Path -ChildPath 'Fonts';
[String]$Script:FontsRegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts';
[String[]]$Script:SupportedExtensions = @('.ttf', '.otf', '.ttc');

# P/Invoke for font registration
$Script:FontApiDefinition = @'
[DllImport("gdi32.dll", CharSet = CharSet.Auto)]
public static extern int AddFontResource(string lpszFilename);

[DllImport("user32.dll", CharSet = CharSet.Auto)]
public static extern int SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
'@;

function Get-FontFile {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [String]$BlobName,

        [Parameter(Mandatory)]
        [String]$ContainerUrl,

        [Parameter(Mandatory)]
        [String]$SasQueryString
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:FontFile; }

    process {
        [String]$Local:EncodedBlobName = [URI]::EscapeDataString($BlobName) -replace '%2F', '/';
        [String]$Local:BlobUri = "${ContainerUrl}/${Local:EncodedBlobName}?${SasQueryString}";

        [String]$Local:MD5 = Get-BlobMD5 -BlobUri:$Local:BlobUri;

        [System.IO.FileInfo]$Local:FontFile = $null;

        if ($Local:MD5) {
            $Local:FontFile = Find-FileByHash -Hash:$Local:MD5 -Path:$Script:FontCacheFolder;
        }

        if ($Local:FontFile) {
            Invoke-Info "Using cached file for $BlobName";
            return $Local:FontFile;
        }

        [String]$Local:FileName = [System.IO.Path]::GetFileName($BlobName);
        [String]$Local:OutPath = $Script:FontCacheFolder | Join-Path -ChildPath $Local:FileName;

        # If file exists but hash didn't match (or no hash available), use unique name
        if (Test-Path -Path $Local:OutPath) {
            [String]$Local:BaseName = [System.IO.Path]::GetFileNameWithoutExtension($Local:FileName);
            [String]$Local:Extension = [System.IO.Path]::GetExtension($Local:FileName);
            [String]$Local:Unique = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetRandomFileName());
            $Local:OutPath = $Script:FontCacheFolder | Join-Path -ChildPath "${Local:BaseName}_${Local:Unique}${Local:Extension}";
        }

        Invoke-Info "Downloading $BlobName...";

        try {
            Invoke-RestMethod -Uri:$Local:BlobUri -Method:GET -OutFile:$Local:OutPath;
            Unblock-File -Path $Local:OutPath;
        } catch {
            Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:ERROR_BLOB_DOWNLOAD_FAILED -FormatArgs @($BlobName);
        }

        return [System.IO.FileInfo]::new($Local:OutPath);
    }
}

function Test-FontInstalled {
    [CmdletBinding()]
    [OutputType([Boolean])]
    param(
        [Parameter(Mandatory)]
        [String]$FontFileName
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:IsInstalled; }

    process {
        [String]$Local:InstalledPath = $Script:FontsFolder | Join-Path -ChildPath $FontFileName;
        [Boolean]$Local:FileExists = Test-Path -Path $Local:InstalledPath;

        if (-not $Local:FileExists) {
            Invoke-Debug "Font file $FontFileName not found in Fonts folder.";
            return $false;
        }

        # Check registry for any entry pointing to this filename
        [Boolean]$Local:InRegistry = $false;
        $Local:RegistryValues = Get-ItemProperty -Path $Script:FontsRegistryPath -ErrorAction SilentlyContinue;

        if ($Local:RegistryValues) {
            foreach ($Local:Property in $Local:RegistryValues.PSObject.Properties) {
                if ($Local:Property.Value -eq $FontFileName) {
                    $Local:InRegistry = $true;
                    break;
                }
            }
        }

        [Boolean]$Local:IsInstalled = $Local:FileExists -and $Local:InRegistry;
        Invoke-Debug "Font $FontFileName installed check: FileExists=$Local:FileExists, InRegistry=$Local:InRegistry";
        return $Local:IsInstalled;
    }
}

function Get-FontDisplayName {
    [CmdletBinding()]
    [OutputType([String])]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$FontFile
    )

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:DisplayName; }

    process {
        [String]$Local:DisplayName = $null;

        # Try to get font name via Shell COM object
        try {
            $Local:Shell = New-Object -ComObject Shell.Application;
            $Local:Folder = $Local:Shell.Namespace($FontFile.DirectoryName);
            $Local:Item = $Local:Folder.ParseName($FontFile.Name);

            # Property 21 is the Title/Name
            $Local:DisplayName = $Local:Folder.GetDetailsOf($Local:Item, 21);

            if ([String]::IsNullOrWhiteSpace($Local:DisplayName)) {
                # Fallback to property 0 (Name without extension typically)
                $Local:DisplayName = $Local:Folder.GetDetailsOf($Local:Item, 0);
            }
        } catch {
            Invoke-Debug "Failed to get font name via Shell: $_";
        } finally {
            if ($Local:Shell) {
                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($Local:Shell) | Out-Null;
            }
        }

        # Fallback to filename-based name
        if ([String]::IsNullOrWhiteSpace($Local:DisplayName)) {
            $Local:DisplayName = [System.IO.Path]::GetFileNameWithoutExtension($FontFile.Name);
        }

        # Determine font type suffix
        [String]$Local:Extension = $FontFile.Extension.ToLowerInvariant();
        [String]$Local:TypeSuffix = switch ($Local:Extension) {
            '.ttf' { ' (TrueType)' }
            '.ttc' { ' (TrueType)' }
            '.otf' { ' (OpenType)' }
            default { ' (TrueType)' }
        };

        # Add suffix if not already present
        if (-not ($Local:DisplayName -match '\(TrueType\)|\(OpenType\)')) {
            $Local:DisplayName += $Local:TypeSuffix;
        }

        return $Local:DisplayName;
    }
}

function Install-Font {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$FontFile
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [String]$Local:FileName = $FontFile.Name;
        [String]$Local:DestinationPath = $Script:FontsFolder | Join-Path -ChildPath $Local:FileName;

        Invoke-Info "Installing font: $Local:FileName";

        # Copy font to Fonts folder
        try {
            Copy-Item -Path $FontFile.FullName -Destination $Local:DestinationPath -Force;
        } catch {
            Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:ERROR_FONT_COPY_FAILED -FormatArgs @($Local:FileName);
        }

        # Get display name for registry
        [String]$Local:DisplayName = Get-FontDisplayName -FontFile:$FontFile;

        # Register in registry
        try {
            Set-RegistryKey -Path $Script:FontsRegistryPath -Key $Local:DisplayName -Value $Local:FileName -Kind String;
        } catch {
            Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:ERROR_FONT_REGISTRY_FAILED -FormatArgs @($Local:FileName);
        }

        # Load font into current session using P/Invoke
        try {
            $null = $Script:FontApi::AddFontResource($Local:DestinationPath);
        } catch {
            Invoke-Warn "Failed to load font immediately (may require reboot): $_";
        }

        Invoke-Info "Installed font: $Local:DisplayName";
    }
}

function Send-FontChangeNotification {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        # WM_FONTCHANGE = 0x001D, HWND_BROADCAST = 0xFFFF
        [IntPtr]$Local:HWND_BROADCAST = [IntPtr]::new(0xFFFF);
        [UInt32]$Local:WM_FONTCHANGE = 0x001D;

        try {
            $null = $Script:FontApi::SendMessage($Local:HWND_BROADCAST, $Local:WM_FONTCHANGE, [IntPtr]::Zero, [IntPtr]::Zero);
            Invoke-Debug 'Sent WM_FONTCHANGE broadcast.';
        } catch {
            Invoke-Warn "Failed to broadcast font change notification: $_";
        }
    }
}

Invoke-RunMain $PSCmdlet {
    Invoke-EnsureAdministrator;

    # Register exit codes
    $Script:ERROR_BLOB_DOWNLOAD_FAILED = Register-ExitCode -Description 'Failed to download blob {0}';
    $Script:ERROR_FONT_COPY_FAILED = Register-ExitCode -Description 'Failed to copy font {0} to Fonts folder';
    $Script:ERROR_FONT_REGISTRY_FAILED = Register-ExitCode -Description 'Failed to register font {0} in registry';

    # Add P/Invoke type
    try {
        $Script:FontApi = Add-Type -MemberDefinition $Script:FontApiDefinition -Name 'FontApi' -Namespace 'AMT' -PassThru;
    } catch {
        # Type may already exist from previous run
        $Script:FontApi = [AMT.FontApi];
    }

    # Ensure cache folder exists
    if (-not (Test-Path -Path $Script:FontCacheFolder)) {
        $null = New-Item -Path $Script:FontCacheFolder -ItemType Directory -Force;
        Invoke-Debug "Created font cache folder: $Script:FontCacheFolder";
    }

    # Normalize container URL (remove trailing slash)
    $StorageBlobUrl = $StorageBlobUrl.TrimEnd('/');

    # Parse SAS token
    [String]$Local:SasQueryString = ConvertTo-SasQueryString -SasToken:$StorageBlobSasToken;

    # List all font blobs
    [String[]]$Local:FontBlobs = Get-BlobList -ContainerUrl:$StorageBlobUrl -SasQueryString:$Local:SasQueryString;

    if ($Local:FontBlobs.Count -eq 0) {
        Invoke-Info 'No font files found in container.';
        return;
    }

    [Int32]$Local:InstalledCount = 0;
    [Int32]$Local:SkippedCount = 0;

    foreach ($Local:BlobName in $Local:FontBlobs) {
        [String]$Local:FileName = [System.IO.Path]::GetFileName($Local:BlobName);

        # Check if already installed
        if (Test-FontInstalled -FontFileName:$Local:FileName) {
            Invoke-Debug "Font $Local:FileName is already installed, skipping.";
            $Local:SkippedCount++;
            continue;
        }

        # Get font file (from cache or download)
        [System.IO.FileInfo]$Local:FontFile = Get-FontFile -BlobName:$Local:BlobName -ContainerUrl:$StorageBlobUrl -SasQueryString:$Local:SasQueryString;

        # Install the font
        Install-Font -FontFile:$Local:FontFile;
        $Local:InstalledCount++;
    }

    # Broadcast font change if any fonts were installed
    if ($Local:InstalledCount -gt 0) {
        Send-FontChangeNotification;
    }

    Invoke-Info "Font installation complete. Installed: $Local:InstalledCount, Skipped (already installed): $Local:SkippedCount";
};
