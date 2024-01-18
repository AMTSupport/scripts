[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(HelpMessage='This directory to source scripts from.')]
    [String]$SourceDir = "./src",

    [Parameter(HelpMessage='The directory to output compiled scripts to.')]
    [String]$OutputDir = "./compiled"
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

    [String]$Local:RelativePath = $CurrentPath.Substring($SourcePath.Length)
    [String]$Local:TargetPath = Join-Path $TargetBasePath $Local:RelativePath

    if (-not (Test-Path -Path $Local:TargetPath)) {
        New-Item -ItemType Directory -Path $Local:TargetPath | Out-Null
    }
}

# Recursively create directory structure and compile scripts
function Invoke-CompileScripts {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$SourceDir,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$OutputDir
    )

    [Object[]]$Local:Items = Get-ChildItem -Path $SourceDir -Recurse

    foreach ($Local:Item in $Local:Items) {
        if ($Local:Item.PSIsContainer) {
            Invoke-EnsureDirectoryStructure -SourcePath $SourceDir -TargetBasePath $OutputDir -CurrentPath $Local:Item.FullName
        } else {
            [String]$OutputFolderPath = Join-Path $OutputDir $Local:Item.DirectoryName.Substring($SourceDir.Length)

            # Run the compiler command
            .\src\Onefile-Runner.ps1 -CompileScripts $Local:Item.FullName -Output $OutputFolderPath
        }
    }
}

Invoke-CompileScripts -SourceDir $SourceDir -OutputDir $OutputDir
