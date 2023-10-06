#Requires -Version 5.1
#Requires -RunAsAdministrator
# Requires -Modules ("Microsoft.Graph.Users", "Microsoft.Powershell.LocalAccounts")

Param(
    [Parameter()]
    [Switch]$NoModify,

    [Parameter(Position = 0, ValueFromRemainingArguments)]
    [String[]]$UserExceptions = @(),

    [Parameter(DontShow)]
    [String[]]$BaseHiddenUsers = @("localadmin", "nt authority\system", "administrator", "AzureAD\Admin", "AzureAD\AdminO365")
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

#region - ASDI Functions

function Get-Groups {
    begin { Enter-Scope $MyInvocation }

    process {
        $Groups = [ADSI]"WinNT://$env:COMPUTERNAME,computer"
        $Groups = $Groups.psbase.children | Where-Object { $_.psbase.SchemaClassName -eq 'Group' } | ForEach-Object { $_.psbase }

        return $Groups
    }

    end { Exit-Scope $MyInvocation $Groups }
}

function Get-Group([String]$Name) {
    begin { Enter-Scope $MyInvocation }

    process {
        $Group = ([ADSI]"WinNT://$env:COMPUTERNAME/$Name,group").PSBase
        return $Group
    }

    end { Exit-Scope $MyInvocation $Group }
}

function Get-Group {
    $Groups = Get-WmiObject -ComputerName $env:COMPUTERNAME -Class Win32_Group
    $Group = $Groups | Where-Object { $_.Name -eq "Administrators" } | Select-Object -First 1
    return $Group
}

function Get-GroupMembers([ADSI]$Group) {
    begin { Enter-Scope $MyInvocation }

    process {
        $Members = $Group.Invoke("Members") | ForEach-Object { $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null) }
        return $Members
    }

    end { Exit-Scope $MyInvocation $Members }
}

function Is-AzureADUser([ADSI]$User) {
    begin { Enter-Scope $MyInvocation }

    process {
        $Result = $false
        $User = $User.psbase
        $User = $User.InvokeGet("objectSid")
        $User = New-Object System.Security.Principal.SecurityIdentifier($User, 0)
        $User = $User.Translate([System.Security.Principal.NTAccount])
        $User = $User.Value

        if ($User.StartsWith("AzureAD\")) {
            $Result = $true
        }

        write-host $Result

        return $Result
    }

    end { Exit-Scope $MyInvocation $Result }
}

#endregion - ASDI Functions

#region - Admin Functions

function Get-LocalAdmins {
    begin { Enter-Scope $MyInvocation }

    process {
        $Admins = net localgroup administrators
        $Admins = $Admins[6..($Admins.Length - 3)]
        $Admins = $Admins | ForEach-Object { $_.Trim() }
        Write-Debug "Admins before filtering [$($Admins -join ', ')]"

        if ("localadmin" -notin $Admins) {
            Write-Host "The account localadmin could not be found, aborting for safety." -ForegroundColor Red
            Exit 1002
        }

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

#region - Fixup Groups

function Get-LocalUsers {
    Get-CimInstance Win32_UserAccount | Where-Object { $_.Disabled -eq $false }
}

function Get-LocalGroupMembers([Parameter(Mandatory)][String]$Group) {
    $Users = (Get-CimInstance Win32_Group -filter "Name='$Group'" | Get-CimAssociatedInstance | where-object { $_.Disabled -eq $false })
    return $Users
}

function Get-LocalUserGroups([Parameter(Mandatory)][String]$Username) {
    $Groups = (Get-CimInstance Win32_UserAccount -Filter "Name='$Username'" | Get-CimAssociatedInstance -ResultClassName Win32_Group)
    return $Groups
}


function Get-LocalUserWithoutGroups {
    $Users = Get-LocalUsers
    $Users = $Users | Where-Object { $null -eq (Get-LocalUserGroups -Username $_.Name) }
    return $Users
}

function Set-MissingGroup {
    begin { Enter-Scope $MyInvocation }

    process {
        $MissingGroups = Get-LocalUserWithoutGroups

        if (($null -eq $MissingGroups) -or ($MissingGroups.Count -eq 0)) {
            return @()
        }

        foreach ($User in $MissingGroups) {
            switch ($NoModify) {
                $true { Write-Host "Would have added $($User.Name) to Users group" }
                $false { Add-LocalGroupMember -Group "Users" -Member $User.Name | Out-Null }
            }
        }

        return $MissingGroups
    }

    end { Exit-Scope $MyInvocation }
}

#endregion - Fixup Groups

#region - Script Main Entry

function Main {
    $Script:ErrorActionPreference = "Stop"
    # $Script:VerbosePreference = "Continue"
    # $Script:DebugPreference = "Continue"

    $LocalAdmins = Get-LocalAdmins
    $RemovedAdmins = Remove-Admins -Users $LocalAdmins

    $FixedUsers = Set-MissingGroup

    if ($RemovedAdmins.Count -eq 0 -and $FixedUsers.Count -eq 0) {
        Write-Host "No accounts modified"
    } else {
        foreach ($User in $FixedUsers) {
            Write-Host "Fixed user $($User.Name) by adding them to the Users group"
        }

        foreach ($User in $RemovedAdmins) {
            switch ($NoModify) {
                $true { Write-Host "Would have removed user $($User) from the administrators group" }
                $false { Write-Host "Removed user $($User) from the administrators group" }
            }
        }

        Exit 1001 # Exit code to indicate a change was made
    }
}

Main

#endregion - Script Main Entry
