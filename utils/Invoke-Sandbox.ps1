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

Import-Module $PSScriptRoot/../src/common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    Import-Module "$PSScriptRoot/Compiler.ps1" -Function * -Global;

    [String]$Private:CompiledScriptPath = [System.IO.Path]::GetTempFileName().Replace('.tmp', '.ps1');
    [String]$Private:Content = Invoke-Compile -ScriptPath:$ScriptPath;
    $Private:Content | Set-Content -Path:$Private:CompiledScriptPath -Encoding:UTF8;

    Invoke-Sandbox -ScriptPath:$Private:CompiledScriptPath -EnableNetworking;
    Remove-Item -Path:$Private:CompiledScriptPath;
};
