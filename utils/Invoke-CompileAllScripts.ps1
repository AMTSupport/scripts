#Requires -Version 7.1

Using module ../src/common/Environment.psm1
Using module ../src/common/Logging.psm1
Using module ../src/common/Exit.psm1

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(HelpMessage = 'This directory to source scripts from.')]
    [String]$SourceDir = "$PSScriptRoot/../src",

    [Parameter(HelpMessage = 'The directory to output compiled scripts to.')]
    [String]$OutputDir = "$PSScriptRoot/../compiled",

    [Parameter(DontShow, HelpMessage = 'The compiler scripts location.')]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [String]$Compiler = "$PSScriptRoot/Compiler.ps1"
)

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

Invoke-RunMain $PSCmdlet {
    Invoke-Info "Compiling scripts from $SourceDir to $OutputDir";

    $Errors = @();
    [Object[]]$Local:Items = Get-ChildItem -Path $SourceDir -Recurse -Filter '*.ps1' -Depth 9 -File;
    foreach ($Local:Item in $Local:Items) {
        [String]$Local:Content = Get-Content -Path $Local:Item.FullName;
        if (($Local:Content.Length -eq 0) -or (Select-String -InputObject $Local:Content -Pattern '^\s*#.*@compile-ignore')) {
            Invoke-Info "Ignoring $($Local:Item.FullName)";
            continue;
        }

        Invoke-Info "Compiling $($Local:Item.FullName)";

        [String]$Local:RelativePath = $Local:Item.DirectoryName.Substring((Get-Item $SourceDir).FullName.Length).TrimStart('\');
        [String]$Local:OutputFolderPath = Join-Path $OutputDir $Local:RelativePath;
        [String]$Local:OutputFilePath = Join-Path $Local:OutputFolderPath $Local:Item.Name;
        Invoke-EnsureDirectoryStructure -SourcePath $SourceDir -TargetBasePath $OutputDir -CurrentPath ($Local:Item.FullName | Split-Path -Parent);

        $Result = Start-Process `
            -FilePath $Compiler `
            -ArgumentList "--input ""$($Local:Item.FullName)"" --output ""$Local:OutputFilePath"" --force $($VerbosePreference -eq 'Continue' ? '--verbose' : '') $($DebugPreference -eq 'Continue' ? '--debug' : '')" `
            -Wait -NoNewWindow -PassThru;

        if ($Result.ExitCode -ne 0) {
            Invoke-Error "Failed to compile $($Local:Item.FullName)";
            return;
        }
    }
}
