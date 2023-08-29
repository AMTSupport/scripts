#Requires -Version 5.1
#Requires -RunAsAdministrator

Param(
    [Parameter()]
    [Switch]$NoModify,

    [Parameter(Position = 0, ValueFromRemainingArguments)]
    [String[]]$UserExceptions = @(),

    [Parameter(DontShow)]
    [String[]]$BaseHiddenUsers = @("localadmin", "nt authority\\system", "administrator", "AzureAD\\Admin")
)

#region - Scope Functions

function Enter-Scope([System.Management.Automation.InvocationInfo]$Invocation) {
    $Params = $Invocation.BoundParameters
    Write-Verbose "Entered scope $($Invocation.MyCommand.Name) with parameters [$($Params.Keys) = $($Params.Values)]"
}

function Exit-Scope([System.Management.Automation.InvocationInfo]$Invocation, [Object]$ReturnValue) {
    Write-Verbose "Exited scope $($Invocation.MyCommand.Name) with return value [$ReturnValue]"
}

#endregion Scope Functions

#region - Script Functions

function Get-LocalAdmins {
    begin { Enter-Scope $MyInvocation }

    process {
        $Admins = net localgroup administrators
        $Admins = $Admins[6..($Admins.Length - 3)]
        $Admins = $Admins | ForEach-Object { $_.Trim() }
        Write-Debug "Admins before filtering [$($Admins -join ', ')]"

        $Admins = $Admins | Where-Object { $_ -notin $BaseHiddenUsers }
        Write-Debug "Admins after filtering [$($Admins -join ', ')]"

        return $Admins
    }

    end { Exit-Scope $MyInvocation $Admins }
}

function Remove-Admins([String[]]$Users) {
    begin { Enter-Scope $MyInvocation }

    process {
        if (($null -eq $Users) -or ($Users.Count -eq 0)) {
            Write-Host "No users were supplied, nothing to do."
            return @()
        }

        Write-Debug "Users before filtering supplied exceptions [$($Users -join ', ')]"
        $Removing = $Users | Where-Object {
            $User = $_
            $Result = $User -notin $UserExceptions
            switch ($Result) {
                $true { Write-Debug "User $User not in exceptions" }
                $false { Write-Debug "User $User in exceptions" }
            }
            $Result
        }
        Write-Debug "Users after filtering supplied exceptions [$($Removing -join ', ')]"

        if (($null -eq $Removing) -or ($Removing.Count -eq 0)) {
            Write-Host "No users after filtering, nothing to do."
            return @()
        }

        foreach ($User in $Removing) {
            switch ($NoModify) {
                $true { Write-Host "Would have removed $User from administrators group" }
                $false { net localgroup administrators /del $User | Out-Null }
            }
        }

        return $Removing
    }

    end { Exit-Scope $MyInvocation $Removing }
}

#endregion - Script Functions

#region - Script Main Entry

function Main {
    $Script:ErrorActionPreference = "Stop"
    $Script:VerbosePreference = "Continue"
    $Script:DebugPreference = "Continue"

    $LocalAdmins = Get-LocalAdmins
    $RemovedAdmins = Remove-Admins -Users $LocalAdmins

    if ($RemovedAdmins.Count -eq 0) {
        Write-Host "No accounts modified"
    } else {
        switch ($NoModify) {
            $true { Write-Host "Would have modified $RemovedAdmins" }
            $false { Write-Host "Modified $RemovedAdmins" }
        }

        Exit 1001 # Exit code to indicate a change was made
    }
}

Main

#endregion - Script Main Entry
