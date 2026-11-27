[CmdletBinding()]
param(
    # Specifies a path to one or more locations.
    [Parameter(Mandatory=$true,
               ValueFromPipeline=$true,
               ValueFromPipelineByPropertyName=$true,
               HelpMessage="Path to the script to execute in the sandbox.")]
    [Alias("PSPath")]
    [ValidateNotNullOrEmpty()]
    [String]$ScriptPath
)

$Script:Template = <#xml#> @'
<?xml version="1.0" encoding="UTF-8"?>
<Configuration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:noNamespaceSchemaLocation="resources/sandbox.schema.xsd">
    <Networking>{2}</Networking>
    <LogonCommand>
      <Command>C:\Temp\{0}</Command>
    </LogonCommand>
    <MappedFolders>
        <MappedFolder>
            <HostFolder>{1}</HostFolder>
            <SandboxFolder>C:\Temp</SandboxFolder>
            <!-- <ReadOnly>True</ReadOnly> -->
        </MappedFolder>
    </MappedFolders>
</Configuration>
'@

function Invoke-Sandbox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true,
                   HelpMessage="Path to the script to execute in the sandbox.")]
        [Alias("PSPath")]
        [ValidateNotNullOrEmpty()]
        [String]$ScriptPath,

        [Switch]$EnableNetworking
    )

    [String]$Private:Template = $Script:Template -f @(($ScriptPath | Split-Path -Leaf), ($ScriptPath | Split-Path -Parent), $EnableNetworking);
    [String]$Private:TempSandboxPath = [System.IO.Path]::GetTempFileName().Replace('.tmp', '.wsb');
    $Private:Template | Out-File -FilePath:$Private:TempSandboxPath -Encoding:UTF8;

    Invoke-Debug "Running script sandbox file $Private:TempSandboxPath";
    Invoke-Debug "Template: $Private:Template"

    Start-Process -FilePath $Private:TempSandboxPath -Wait;
    Remove-Item -Path:$Private:TempSandboxPath;
}

Import-Module $PSScriptRoot/../Output/PowerShellModules/AMT.PowerShell.Common/AMT.PowerShell.Common.psd1;
Invoke-RunMain $PSCmdlet {
    [String]$Private:CompilerDll = Join-Path $PSScriptRoot '../src/Compiler/bin/Debug/Compiler.dll';
    if (-not (Test-Path -Path $Private:CompilerDll -PathType Leaf)) {
        $Private:CompilerDll = Join-Path $PSScriptRoot '../src/Compiler/bin/Release/Compiler.dll';
    }
    if (-not (Test-Path -Path $Private:CompilerDll -PathType Leaf)) {
        throw "Compiler not found. Build it first with: dotnet build src/Compiler/Compiler.csproj";
    }

    [String]$Private:OutputFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName());
    New-Item -Path $Private:OutputFolder -ItemType Directory -Force | Out-Null;

    try {
        & dotnet $Private:CompilerDll --input $ScriptPath --output $Private:OutputFolder --force;
        if ($LASTEXITCODE -ne 0) {
            throw "Compiler exited with code $LASTEXITCODE.";
        }

        [String]$Private:CompiledScriptPath = Join-Path $Private:OutputFolder ([System.IO.Path]::GetFileName($ScriptPath));
        if (-not (Test-Path -Path $Private:CompiledScriptPath -PathType Leaf)) {
            throw "Compiler did not produce '$Private:CompiledScriptPath'.";
        }

        Invoke-Sandbox -ScriptPath $Private:CompiledScriptPath -EnableNetworking;
    } finally {
        Remove-Item -Path $Private:OutputFolder -Recurse -Force -ErrorAction SilentlyContinue;
    }
};
