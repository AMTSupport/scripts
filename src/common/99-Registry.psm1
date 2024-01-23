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
            New-Item -Path $Local:CurrentPath -Force -ItemType RegistryKey;
        }
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

    Invoke-EnsureRegistryPath -Root $Path.Substring(0, 4) -Path $Path.Substring(5);
    if ($PSCmdlet.ShouldProcess($Path, 'Set')) {
        Invoke-Verbose "Setting registry key '$Path'...";
        Set-ItemProperty -Path $Path -Name $Key -Value $Value -Type $Kind;
    }
}

Export-ModuleMember -Function New-RegistryKey, Remove-RegistryKey, Set-RegistryKey, Test-RegistryKey;
