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
    }

    end { Exit-Scope $MyInvocation }
}

function Add-PrinterImpl {
    begin { Enter-Scope $MyInvocation }

    process {
        if (-not (Get-PrinterDriver -Name $PrinterDriver -ErrorAction SilentlyContinue)) {
            Write-Host "Unable to find driver $PrinterDriver"
            Exit 1003
        }

        switch (Get-PrinterPort -Name $PrinterIP -ErrorAction SilentlyContinue) {
            $null {
                Write-Host "Adding printer port $PrinterIP"
                Add-PrinterPort -Name $PrinterIP -PrinterHostAddress $PrinterIP
            }
            default {
                Write-Host "Printer port $PrinterIP already exists"
            }
        }

        switch (Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue) {
            $null {
                Write-Host "Adding printer $PrinterName"
                Add-Printer -Name $PrinterName -DriverName $PrinterDriver -PortName $PrinterIP
            }
            default {
                Write-Host "Printer $PrinterName already exists"
            }
        }
    }

    end { Exit-Scope $MyInvocation }
}

function Main {
    Add-PrinterDriverImpl
    Add-PrinterImpl
}

Main
