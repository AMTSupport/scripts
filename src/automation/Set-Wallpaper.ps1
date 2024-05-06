[CmdletBinding(DefaultParameterSetName = 'Set_Base64')]
param(
    [Parameter(ParameterSetName = 'Set_StorageBlob')]
    [String]$StorageBlobUrl,

    [Parameter(ParameterSetName = 'Set_StorageBlob')]
    [String]$StorageBlobSasToken,

    [Parameter(Mandatory, ParameterSetName = 'Set_Base64')]
    [ValidateNotNullOrEmpty()]
    [String]$Base64Image,

    [Parameter(Mandatory, ParameterSetName = 'Encode')]
    [ValidateNotNullOrEmpty()]
    [Alias('PSPath')]
    [String]$Path,

    [Parameter(Mandatory, ParameterSetName = 'Reset')]
    [Switch]$Reset
)

[String]$Script:WallpaperFolder = $env:ProgramData | Join-Path -ChildPath 'AMT' | Join-Path -ChildPath 'Wallpapers';

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
    end { Exit-Scope -ReturnValue $Local:File.FullName; }

    process {
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

function Export-ToFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Base64Content
    )

    begin {
        Enter-Scope -ArgumentFormatter:@{
            Base64Content = { $_.Substring(0, 36) + '...' }
        }
    }
    end { Exit-Scope; }

    process {
        [System.IO.FileInfo]$Local:TmpFile = New-Item -Path $env:TEMP -Name ([System.IO.Path]::GetTempFileName()) -ItemType File -Force;
        [System.IO.File]::WriteAllBytes($TmpFile, [System.Convert]::FromBase64String($Base64Content));

        Set-Permissions -Path $Local:TmpFile;

        return $Local:TmpFile;
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
    end { Exit-Scope -ReturnValue $Local:OutPath; }

    process {
        [String]$Local:Uri = "${Url}?${SasToken}";

        Invoke-Debug "Calling HEAD on $Local:Uri to get MD5 hash...";
        $Local:ResponseHeaders = Invoke-WebRequest -Uri:$Local:Uri -Method:HEAD | Select-Object -ExpandProperty Headers;
        [String]$Local:MD5 = $Local:ResponseHeaders['Content-MD5'];

        [System.IO.FileInfo]$Local:ExistingFile = Find-FileByHash -Hash:$Local:MD5 -Path:$Script:WallpaperFolder -Filter:'*.png';

        if ($Local:ExistingFile) {
            Invoke-Info "Using existing file {$Local:ExistingFile}...";
            return $Local:ExistingFile;
        }

        [String]$Local:OutPath = $Script:WallpaperFolder | Join-Path -ChildPath ([System.IO.Path]::GetRandomFileName() + '.png');
        Invoke-RestMethod -Uri:$Local:Uri -Method:GET -OutFile:$Local:OutPath;

        Unblock-File -Path $Local:OutPath;
        Set-Permissions -Path $Local:OutPath;

        return $Local:OutPath;
    }
}

function Set-Permissions {
    param(
        [Parameter(Mandatory)]
        [String]$Path
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [System.Security.AccessControl.FileSecurity]$Local:ACL = Get-Acl -Path $Path;
        $Local:ACL.SetAccessRuleProtection($true, $false);
        $Local:ACL.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule('Users', 'Read', 'Allow')));

        Set-Acl -Path $Path -AclObject $Local:ACL;
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
        $Path = $Path.Trim();
        [String]$Private:RegPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP';

        Invoke-Info 'Settings Registry Keys';
        Set-RegistryKey -Path $Private:RegPath -Key 'DesktopImagePath' -Value $Path -Kind String;
        Set-RegistryKey -Path $Private:RegPath -Key 'DesktopImageUrl' -Value $Path -Kind String;
        Set-RegistryKey -Path $Private:RegPath -Key 'DesktopImageStatus' -Value 1 -Kind DWord;

        Invoke-OnEachUserHive {
            param($Hive)

            [String]$Private:RegPath = "HKCU:\$($Hive.SID)\Control Panel\Desktop";
            Set-RegistryKey -Path:$Private:RegPath -Key:'Wallpaper' -Value:$Path -Kind:String;
            Set-RegistryKey -Path:$Private:RegPath -Key:'WallpaperStyle' -Value:$StyleNum[$Style] -Kind:DWord;
        }

        Update-PerUserSystemParameters;
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

        Update-PerUserSystemParameters;
    }
}

function Update-PerUserSystemParameters {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $Local:ScriptBlock = {
            # For some reason, we need to run this multiple times to get it to work
            for ($i = 0; $i -lt 50; $i++) {
                rundll32.exe user32.dll, UpdatePerUserSystemParameters;
            }
        }

        if (Test-IsRunningAsSystem) {
            Invoke-EnsureModule 'RunAsUser';
            Invoke-AsCurrentUser -ScriptBlock $Local:ScriptBlock;
        }
        else {
            & $Local:ScriptBlock;
        }
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
        }
        else {
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
    Invoke-EnsureAdministrator;

    if (-not (Test-Path -Path $Script:WallpaperFolder)) {
        New-Item -Path $Script:WallpaperFolder -ItemType Directory -Force;
    }

    switch ($PSCmdlet.ParameterSetName) {
        'Set_Base64' {
            Invoke-Info 'Setting wallpaper...';

            [System.IO.FileInfo]$Local:ImagePath = Export-ToFile -Base64Content $Base64Image;
            [System.IO.FileInfo]$Local:ImagePath = Get-ReusableFile -Path $Local:ImagePath;
            Set-Wallpaper -Path:$Local:ImagePath;
        }
        'Set_StorageBlob' {
            Invoke-Info 'Setting wallpaper...';

            [String]$Local:ImagePath = Get-FromBlob -Url $StorageBlobUrl -SasToken $StorageBlobSasToken;

            Invoke-Info "Using image from $Local:ImagePath...";

            Set-Wallpaper -Path:$Local:ImagePath;
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
