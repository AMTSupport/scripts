[CmdletBinding(DefaultParameterSetName='Set_Base64')]
param(
    [Parameter(ParameterSetName='Set_StorageBlob')]
    [String]$StorageBlobUrl,

    [Parameter(ParameterSetName='Set_StorageBlob')]
    [String]$StorageBlobSasToken,

    [Parameter(Mandatory, ParameterSetName='Set_Base64')]
    [ValidateNotNullOrEmpty()]
    [String]$Base64Image,

    [Parameter(Mandatory, ParameterSetName='Encode')]
    [ValidateNotNullOrEmpty()]
    [Alias('PSPath')]
    [String]$Path,

    [Parameter(Mandatory, ParameterSetName='Reset')]
    [Switch]$Reset
)

[String]$Script:WallpaperFolder = 'C:\temp\';

function Invoke-EncodeFromFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]$Path
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [Byte[]]$Content = [System.IO.File]::ReadAllBytes($Path);
        [String]$Base64Content = [System.Convert]::ToBase64String($Content);

        return $Base64Content;
    }
}

function Find-FileByHash {
    param(
        [Parameter(Mandatory)]
        [String]$Hash,

        [Parameter(Mandatory)]
        [Object]$Path,

        [String]$Filter = '*'
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        foreach ($Local:File in Get-ChildItem -Path $Path -File -Filter:$Filter) {
            [String]$Local:FileHash = Get-FileHash -Path $Local:File.FullName -Algorithm MD5;
            if ($Local:FileHash -eq $Hash) {
                return $Local:File;
            }
        }

        return $null;
    }
}

function Export-ToFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Base64Content
    )

    begin { Enter-Scope -ArgumentFormatter:@{
        Base64Content = { $_.Substring(0, 36) + '...' }
    }}
    end { Exit-Scope; }

    process {
        [System.IO.FileInfo]$Local:TmpFile = New-Item -Path $env:TEMP -Name ([System.IO.Path]::GetTempFileName()) -ItemType File -Force;
        [System.IO.File]::WriteAllBytes($TmpFile, [System.Convert]::FromBase64String($Base64Content));

        return $Path;
    }
}

function Get-FromBlob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]$Url,

        [Parameter(Mandatory)]
        [String]$SasToken
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [String]$Local:Uri = "${Url}?${SasToken}";

        Invoke-Debug "Calling HEAD on $Local:Uri to get MD5 hash...";
        Invoke-RestMethod -Uri:$Local:Uri -Method:HEAD -ResponseHeadersVariable:ResponseHeaders;
        [String]$Local:MD5 = $ResponseHeaders['Content-MD5'];

        [System.IO.FileInfo]$Local:ExistingFile = Find-FileByHash -Hash:$Local:MD5 -Path:$Script:WallpaperFolder -Filter:'*.png';

        if ($Local:ExistingFile) {
            return $Local:ExistingFile;
        }

        [String]$Local:OutPath = [System.IO.Path]::Combine($env:TEMP, [System.IO.Path]::GetTempFileName());
        Invoke-RestMethod -Uri:$Local:Uri -Method:GET -OutFile:$Local:OutPath;

        return $Local:OutPath;
    }
}

function Set-Wallpaper {
    param(
        [Parameter(Mandatory)]
        [String]$Path,

        [ValidateSet('Tile', 'Center', 'Stretch', 'Fill', 'Fit', 'Span')]
        [String]$Style = 'Fill'
    )

    begin {
        Enter-Scope;

        try {
            Add-Type @'
                using System;
                using System.Runtime.InteropServices;
                using Microsoft.Win32;
                namespace Wallpaper {
                    public enum Style : int {
	                    Tile, Center, Stretch, Fill, Fit, Span, NoChange
                    }

                    public class Setter {
                        // public const int SetDesktopWallpaper = 20;
	                    // public const int UpdateIniFile = 0x01;
	                    // public const int SendWinIniChange = 0x02;

                        // [DllImport( "user32.dll", SetLastError = true, CharSet = CharSet.Auto )]
	                    // private static extern int SystemParametersInfo (int uAction, int uParam, string lpvParam, int fuWinIni);

                        public static void SetWallpaper(string path, Wallpaper.Style style) {
		                    // SystemParametersInfo(SetDesktopWallpaper, 0, path, UpdateIniFile | SendWinIniChange);
		                    RegistryKey key = Registry.CurrentUser.OpenSubKey("Control Panel\\Desktop", true);
		                    switch(style) {
			                    case Style.Tile :
                                    key.SetValue(@"WallpaperStyle", "0") ;
                                    key.SetValue(@"TileWallpaper", "1") ;
                                    break;
			                    case Style.Center :
                                    key.SetValue(@"WallpaperStyle", "0") ;
                                    key.SetValue(@"TileWallpaper", "0") ;
                                    break;
			                    case Style.Stretch :
                                    key.SetValue(@"WallpaperStyle", "2") ;
                                    key.SetValue(@"TileWallpaper", "0") ;
                                    break;
			                    case Style.Fill :
                                    key.SetValue(@"WallpaperStyle", "10") ;
                                    key.SetValue(@"TileWallpaper", "0") ;
                                    break;
			                    case Style.Fit :
                                    key.SetValue(@"WallpaperStyle", "6") ;
                                    key.SetValue(@"TileWallpaper", "0") ;
                                    break;
			                    case Style.Span :
                                    key.SetValue(@"WallpaperStyle", "22") ;
                                    key.SetValue(@"TileWallpaper", "0") ;
                                    break;
			                    case Style.NoChange :
                                    break;
		                    }
		                    key.Close();
	                    }
                    }
                }
'@
        } catch {}

        $StyleNum = @{
            Tile    = 0
            Center  = 1
            Stretch = 2
            Fill    = 3
            Fit     = 4
            Span    = 5
        }
    }
    end { Exit-Scope; }

    process {
        $Local:RegPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP';

        Invoke-Info 'Settings Registry Keys';
        Set-RegistryKey -Path $Local:RegPath -Key 'DesktopImagePath' -Value $Path -Kind String;
        Set-RegistryKey -Path $Local:RegPath -Key 'DesktopImageUrl' -Value $Path -Kind String;
        Set-RegistryKey -Path $Local:RegPath -Key 'DesktopImageStatus' -Value 1 -Kind DWord;

        # ForEach for all users, load the .dat hive and set the wallpaper
        [Wallpaper.Setter]::SetWallpaper($Path, $StyleNum[$Style]);

        rundll32.exe user32.dll, UpdatePerUserSystemParameters;
    }
}

function Remove-Wallpaper {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $Local:RegPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP';

        Remove-RegistryKey -Path $Local:RegPath -Key 'DesktopImagePath';
        Remove-RegistryKey -Path $Local:RegPath -Key 'DesktopImageUrl';
        Remove-RegistryKey -Path $Local:RegPath -Key 'DesktopImageStatus';

        rundll32.exe user32.dll, UpdatePerUserSystemParameters;
    }
}

function Get-ReusableFile {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$Path
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [System.IO.DirectoryInfo]$Local:WallpaperFolder = Get-Item -Path $Script:WallpaperFolder;
        [System.IO.FileInfo]$Local:ExistingFile = Find-FileByHash -Hash:(Get-FileHash -Path $Path -Algorithm MD5) -Path:$Local:WallpaperFolder -Filter:'*.png';
        if ($Local:ExistingFile) {
            Remove-Item -Path $Path; # Remove the file if it is the same as an existing file.
            $Path = $Local:ExistingFile;
        } else {
            # Enter Loop to ensure unique file name
            do {
                [System.IO.DirectoryInfo]$Local:FileName = [IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetRandomFileName()) + '.png';
                [System.IO.FileInfo]$Local:NewPath = [System.IO.Path]::Combine($WallpaperFolder.FullName, $FileName);
            } while (Test-Path -Path $Path);

            Move-Item -Path:$Path -Destination:$Local:NewPath;
            $Path = $Local:NewPath;
        }

        return $Path;
    }
}

Import-Module $PSScriptRoot/../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    return
    Invoke-EnsureAdministrator;

    switch ($PSCmdlet.ParameterSetName) {
        'Set_Base64' {
            Invoke-Info 'Setting wallpaper...';

            [System.IO.FileInfo]$Local:ImagePath = Export-ToFile -Base64Content $Base64Image;
            [System.IO.FileInfo]$Local:ImagePath = Get-ReusableFile -Path $Local:ImagePath;
            Set-Wallpaper -Path $Local:ImagePath;
        }
        'Set_StorageBlob' {
            Invoke-Info 'Setting wallpaper...';

            [String]$Local:ImagePath = Get-FromBlob -Url $StorageBlobUrl -SasToken $StorageBlobSasToken;

            Set-Wallpaper -Path $Local:ImagePath;
        }
        'Encode' {
            Invoke-Info 'Encoding image to base64...';

            $Local:Base64Content = Invoke-EncodeFromFile -Path:(Resolve-Path -Path $Path);
            return $Local:Base64Content;
        }
        'Reset' {
            Invoke-Info 'Removing wallpaper...';

            Remove-Wallpaper;
        }
        default {
            throw 'Invalid parameter set';
        }
    }
};
