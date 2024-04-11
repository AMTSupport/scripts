#Requires -Version 7.1

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(HelpMessage='This directory to source scripts from.')]
    [String]$SourceDir = "$PSScriptRoot/../src",

    [Parameter(HelpMessage='The directory to output compiled scripts to.')]
    [String]$OutputDir = "$PSScriptRoot/../compiled",

    [Parameter(DontShow, HelpMessage='The compiler scripts location.')]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [String]$CompilerScript = "$PSScriptRoot/Compiler.ps1"
)

# Function to create directory structure
function Invoke-EnsureDirectoryStructure {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$SourcePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$TargetBasePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$CurrentPath
    )

    [String]$RelativePath = $CurrentPath.Substring((Get-Item $SourcePath).FullName.Length).TrimStart('\');
    [String]$Local:TargetPath = Join-Path $TargetBasePath $Local:RelativePath;

    while (-not (Test-Path -Path $Local:TargetPath)) {
        Invoke-Info "Creating Parent Directory $Local:TargetPath";
        New-Item -ItemType Directory -Path $Local:TargetPath | Out-Null;
        [String]$Local:TargetPath = Split-Path -Path $Local:TargetPath -Parent;
    }

    if (-not (Test-Path -Path $Local:TargetPath)) {
        Invoke-Info "Creating Directory $Local:TargetPath";
        New-Item -ItemType Directory -Path $Local:TargetPath | Out-Null;
    }
}

Import-Module $PSScriptRoot/../src/common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    Invoke-Info "Compiling scripts from $SourceDir to $OutputDir";
    Invoke-EnsureModule "$PSScriptRoot/Compiler.ps1";

    [Object[]]$Local:Items = Get-ChildItem -Path $SourceDir -Recurse -Filter '*.ps1';
    foreach ($Local:Item in $Local:Items) {
        [String]$Local:Content = Get-Content -Path $Local:Item.FullName;
        if (($Local:Content.Length -eq 0) -or (Select-String -InputObject $Local:Content -Pattern '^\s*#.*@compile-ignore')) {
            Invoke-Info "Ignoring $($Local:Item.FullName)";
            continue;
        }

        Invoke-Info "Compiling $($Local:Item.FullName)";

        # Get the relative path of the file
        [String]$Local:RelativePath = $Local:Item.DirectoryName.Substring((Get-Item $SourceDir).FullName.Length).TrimStart('\');
        [String]$Local:OutputFolderPath = Join-Path $OutputDir $Local:RelativePath;

        Invoke-EnsureDirectoryStructure -SourcePath $SourceDir -TargetBasePath $OutputDir -CurrentPath ($Local:Item.FullName | Split-Path -Parent);
        [System.IO.FileInfo]$Local:OutputFile = Join-Path -Path $Local:OutputFolderPath -ChildPath $Local:Item.Name;

        [String]$Local:CompiledScript = Invoke-Compile -ScriptPath $Local:Item.FullName;
        Set-Content -Path $Local:OutputFile -Value $Local:CompiledScript;
    }
}
