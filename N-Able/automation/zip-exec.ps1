Param(
    [Parameter(Mandatory=$true)]
    [string]$ZipURL,

    [Parameter(Mandatory=$true)]
    [string]$ExecName,

    [Parameter(Position = 0, ValueFromRemainingArguments)]
    [string[]]$ExecArgs,

    [Parameter()]
    [switch]$DryRun
)

#region - Scope Functions

function Enter-Scope([System.Management.Automation.InvocationInfo]$Invocation) {
    $Params = $Invocation.BoundParameters
    Write-Host "Entered scope $($Invocation.MyCommand.Name) with parameters [$($Params.Keys) = $($Params.Values)]"
}

function Exit-Scope([System.Management.Automation.InvocationInfo]$Invocation) {
    Write-Host "Exited scope $($Invocation.MyCommand.Name)"
}

#endregion - Scope Functions

function Get-ExecPath([Parameter(Mandatory)][string]$URL, [Parameter(Mandatory)][string]$FName) {
    begin { Enter-Scope $MyInvocation }

    process {
        $OutFolder = "$env:TEMP\$($URL.Split('/')[-1].Split('.')[0])"

        Write-Host "Downloading $URL to $OutFolder.zip"
        Invoke-WebRequest -Uri $URL -OutFile "$OutFolder.zip" -UseBasicParsing

        Write-Host "Extracting $OutFolder.zip to $OutFolder"
        Expand-Archive -Path "$OutFolder.zip" -DestinationPath $OutFolder -Force

        Write-Host "Looking for $FName at $OutFolder\$FName"
        $ExecPath = "$OutFolder\$FName"
        if (!(Test-Path $ExecPath)) {
            Write-Host "Could not find executable at $ExecPath"
            exit 1003
        }

        return $ExecPath
    }

    end { Exit-Scope $MyInvocation }
}

function Invoke-Exec([Parameter(Mandatory)][string]$ExecPath, [string[]]$ExecArgs) {
    begin { Enter-Scope $MyInvocation }

    process {
        if ($DryRun) {
            Write-Host "Dry run: $ExecPath $ExecArgs"
            return
        }

        Write-Host "Executing $ExecPath $ExecArgs"
        & $ExecPath $ExecArgs
    }

    end { Exit-Scope $MyInvocation }
}

function Main {
    $ExecPath = Get-ExecPath $ZipURL $ExecName
    Invoke-Exec $ExecPath $ExecArgs
}

Main


