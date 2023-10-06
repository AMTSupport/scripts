Param(
    [Parameter(Mandatory)]
    [String]$PrinterName,

    [Parameter(Mandatory)]
    [String]$PrinterIP,

    [Parameter(Mandatory)]
    [String]$PrinterDriver,

    [Parameter()]
    [String]$ChocoDriver
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


function Add-PrinterDriverImpl {
    begin { Enter-Scope $MyInvocation }

    process {
        if (($null -ne $ChocoDriver) -and ($ChocoDriver -ne "")) {
            Import-Module "$($env:SystemDrive)\ProgramData\Chocolatey\Helpers\chocolateyProfile.psm1" -Force
            refreshenv | Out-Null

            try {
                choco install -y -e --limit-output $ChocoDriver
            }
            catch {
                Write-Host "Failed to install driver $ChocoDriver"
                Write-Host $_
                Exit 1001
            }
        }

        Write-Host "No choco driver to install."
    }

    end { Exit-Scope $MyInvocation }
}

function Add-PrinterImpl {
    begin { Enter-Scope $MyInvocation }

    process {
        $DriverWait = 0
        while (-not (Get-PrinterDriver -Name $PrinterDriver -ErrorAction SilentlyContinue)) {
            if ($DriverWait -gt 300) {
                Write-Host "Unable to find driver $PrinterDriver"
                Exit 1002
            }

            Write-Host "Waiting for driver $PrinterDriver"
            Start-Sleep -Seconds 5
            $DriverWait += 5
        }

        if (-not (Get-PrinterPort -Name $PrinterIP -ErrorAction SilentlyContinue)) {
            Write-Host "Adding printer port $PrinterIP"
            Add-PrinterPort -Name $PrinterIP -PrinterHostAddress $PrinterIP
        } else {
            Write-Host "Printer port $PrinterIP already exists"
        }

        if (-not (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue)) {
            Write-Host "Adding printer $PrinterName"
            Add-Printer -Name $PrinterName -DriverName $PrinterDriver -PortName $PrinterIP
        } else {
            Write-Host "Printer $PrinterName already exists"
        }
    }

    end { Exit-Scope $MyInvocation }
}

function Main {
    Add-PrinterDriverImpl
    Add-PrinterImpl
}

Main
