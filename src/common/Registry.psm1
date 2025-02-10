Using module .\Logging.psm1
Using module .\Scope.psm1

function Invoke-EnsureRegistryPath {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateSet('HKLM', 'HKCU')]
        [String]$Root,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [String]$Path
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [String[]]$Local:PathParts = $Path.Split('\') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) };
        [String]$Local:CurrentPath = "${Root}:";

        foreach ($Local:PathPart in $Local:PathParts) {
            [String]$Local:CurrentPath = Join-Path -Path $Local:CurrentPath -ChildPath $Local:PathPart;
            if (Test-Path -Path $Local:CurrentPath -PathType Container) {
                Invoke-Verbose "Registry key '$Local:CurrentPath' already exists.";
                continue;
            }

            if ($PSCmdlet.ShouldProcess($Local:CurrentPath, 'Create')) {
                Invoke-Verbose "Creating registry key '$Local:CurrentPath'...";
                $null = New-Item -Path $Local:CurrentPath -Force -ItemType RegistryKey;
            }
        }
    }
}

function Test-RegistryKey {
    [CmdletBinding()]
    [OutputType([Boolean])]
    param (
        [Parameter(Mandatory)]
        [String]$Path,

        [Parameter(Mandatory)]
        [String]$Key
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        if (Test-Path -Path $Path -PathType Container) {
            if (Get-ItemProperty -Path $Path -Name $Key -ErrorAction SilentlyContinue) {
                return $True;
            }
        }

        return $False;
    }
}

function Get-RegistryKey {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [String]$Path,

        [Parameter(Mandatory)]
        [String]$Key
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        if (Test-RegistryKey -Path $Path -Key $Key) {
            return Get-ItemProperty -Path $Path -Name $Key | Select-Object -ExpandProperty $Key;
        }

        return $Null;
    }
}

function Set-RegistryKey {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [String]$Path,

        [Parameter(Mandatory)]
        [String]$Key,

        [Parameter(Mandatory)]
        [String]$Value,

        [Parameter(Mandatory)]
        [ValidateSet('Binary', 'DWord', 'ExpandString', 'MultiString', 'None', 'QWord', 'String')]
        [Microsoft.Win32.RegistryValueKind]$Kind
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        Invoke-EnsureRegistryPath -Root $Path.Substring(0, 4) -Path $Path.Substring(5);
        if ($PSCmdlet.ShouldProcess($Path, 'Set')) {
            Invoke-Verbose "Setting registry key '$Path' to '$Value'...";
            Set-ItemProperty -Path $Path -Name $Key -Value $Value -Type $Kind;
            [Microsoft.Win32.Registry]::SetValue($Path, $Key, $Value, $Kind);
        }
    }
}

function Remove-RegistryKey {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [String]$Path,

        [Parameter(Mandatory)]
        [String]$Key
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        if (-not (Test-RegistryKey -Path $Path -Key $Key)) {
            Invoke-Verbose "Registry key '$Path\$Key' does not exist.";
            return;
        }

        if ($PSCmdlet.ShouldProcess($Path, 'Remove')) {
            Invoke-Verbose "Removing registry key '$Path\$Key'...";
            Remove-ItemProperty -Path $Path -Name $Key;
        }
    }
}

function Get-AllSIDs {
    $PatternSID = '(?:S-1-5-21|S-1-12-1)-\d+-\d+\-\d+\-\d+$'
    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*' `
    | Where-Object { $_.PSChildName -match $PatternSID } `
    | Select-Object @{name = 'SID'; expression = { $_.PSChildName } },
    @{name = 'UserHive'; expression = { "$($_.ProfileImagePath)\ntuser.dat" } },
    @{name = 'Username'; expression = { $_.ProfileImagePath -replace '^(.*[\\\/])', '' } } `
    | Where-Object { Test-Path -Path $_.UserHive };
}

function Get-UnloadedUserHives {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject[]]$LoadedHives,

        [Parameter(Mandatory)]
        [PSCustomObject[]]$ProfileList
    )

    Compare-Object $ProfileList.SID $LoadedHives.SID | Select-Object @{name = 'SID'; expression = { $_.InputObject } }, UserHive, Username
}

function Get-LoadedUserHives {
    return Get-ChildItem Registry::HKEY_USERS `
    | Where-Object { $_.PSChildname -match $PatternSID } `
    | Select-Object @{name = 'SID'; expression = { $_.PSChildName } };
}

function Invoke-OnEachUserHive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ScriptBlock]$ScriptBlock
    )

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [PSCustomObject[]]$Private:ProfileList = Get-AllSIDs;
        [PSCustomObject[]]$Private:LoadedHives = Get-LoadedUserHives;
        [PSCustomObject[]]$Private:UnloadedHives = Get-UnloadedUserHives -LoadedHives $Private:LoadedHives -ProfileList $Private:ProfileList;

        Invoke-Debug "Loaded hives: $($Private:LoadedHives.SID -join ', ')";
        Invoke-Debug "Unloaded hives: $($Private:UnloadedHives.SID -join ', ')";

        Foreach ($Private:Hive in $Private:ProfileList) {
            Invoke-Verbose "Processing hive '$($Private:Hive)'...";

            $Private:IsUnloadedHive = $Private:Hive.SID -in $Private:UnloadedHives.SID;

            If ($Private:IsUnloadedHive) {
                Invoke-Debug "Loading hive '$($Private:Hive.UserHive)'...";
                reg load "HKU\$($Private:Hive.SID)" $Private:Hive.UserHive;

                if (-not (Test-Path -Path Registry::HKEY_USERS\$($Private:Hive.SID))) {
                    Invoke-Warn "Failed to load hive '$($Private:Hive.UserHive)'.";
                    continue;
                }
            }

            try {
                Invoke-Debug 'Executing script block...';
                & $ScriptBlock -Hive $Private:Hive;
            }
            finally {
                If ($Private:IsUnloadedHive) {
                    Invoke-Debug "Unloading hive '$($Private:Hive.UserHive)'...";
                    [GC]::Collect();
                    reg unload HKU\$($Private:Hive.SID);
                }
            }
        }
    }
}

Export-ModuleMember -Function New-RegistryKey, Remove-RegistryKey, Test-RegistryKey, Get-RegistryKey, Set-RegistryKey, Invoke-OnEachUserHive;
