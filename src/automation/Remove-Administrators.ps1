#Requires -Version 5.1

Param(
    [Parameter()]
    [Switch]$NoModify,

    # Allow limiting to specific machines like AzureAD\casfedi=CASFEDI-PC
    [Parameter(Position = 0, ValueFromRemainingArguments)]
    [String[]]$UserExceptions = @(),

    [Parameter(DontShow)]
    [String[]]$BaseHiddenUsers = @('localadmin', 'nt authority\system', 'administrator', 'AzureAD\Admin', 'AzureAD\AdminO365')
)


#region - ASDI Functions

# function Get-Group {
#     $Groups = Get-WmiObject -ComputerName $env:COMPUTERNAME -Class Win32_Group
#     $Group = $Groups | Where-Object { $_.Name -eq 'Administrators' } | Select-Object -First 1
#     return $Group
# }

# function Is-AzureADUser([ADSI]$User) {
#     begin { Enter-Scope $MyInvocation }

#     process {
#         $Result = $false
#         $User = $User.psbase
#         $User = $User.InvokeGet('objectSid')
#         $User = New-Object System.Security.Principal.SecurityIdentifier($User, 0)
#         $User = $User.Translate([System.Security.Principal.NTAccount])
#         $User = $User.Value

#         if ($User.StartsWith('AzureAD\')) {
#             $Result = $true
#         }

#         Invoke-Info $Result;

#         return $Result
#     }

#     end { Exit-Scope $MyInvocation $Result }
# }

#endregion - ASDI Functions

#region - Admin Functions

function Get-FilteredUsers(
    [Parameter(Mandatory)]
    [ValidateScript({ $_.SchemaClassName -eq 'Group' })]
    [ValidateNotNullOrEmpty()]
    [ADSI]$Group,

    [Parameter(Mandatory)]
    [HashTable[]]$Exceptions
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:FilteredMembers; }

    process {
        [HashTable[]]$Local:Members = Get-GroupMembers -Group $Group | ForEach-Object {
            [HashTable]$Local:Table = Get-FormattedUser -User $_;
            $Local:Table | Add-Member -MemberType NoteProperty -Name ADSI -Value $_;

            $Local:Table
        };

        Invoke-Debug "Members of Administrators group [$(($Local:Members | Select-Object -ExpandProperty Name) -join ', ')]";

        if (-not ($Local:Members | Where-Object { $_.Name -eq 'localadmin' } | Select-Object -First 1)) {
            Invoke-Error 'The account localadmin could not be found, aborting for safety.';
            Invoke-FailedExit -ExitCode 1002;
        }

        [HashTable[]]$Local:FilteredMembers = $Local:Members | Where-Object {
            [String]$Local:Name = $_.Name;
            $Local:Exception = $Exceptions | Where-Object { $_.Name -ieq $Local:Name -and $_.Domain -ieq $env:COMPUTERNAME };

            (-not $Local:Exception) -or ($Local:Exception.Computers -contains $env:COMPUTERNAME)
        };

        Invoke-Info "Admins after filtering [$(($Local:FilteredMembers | Select-Object -ExpandProperty Name) -join ', ')]";
        return $Local:FilteredMembers;
    }
}

function Remove-Admins(
    [Parameter(Mandatory)]
    [ValidateScript({ $_.SchemaClassName -eq 'Group' })]
    [ValidateNotNullOrEmpty()]
    [ADSI]$Group,

    [Parameter(Mandatory)]
    [HashTable[]]$Users,

    [Parameter(Mandatory)]
    [HashTable[]]$Exceptions
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $RemovedUsers; }

    process {
        if (-not $Users -or $Users.Count -eq 0) {
            Invoke-Info 'No non-exception users were supplied, nothing to do.';
            return @();
        }

        $Local:RemovedUsers = $Users | ForEach-Object {
            if (-not $NoModify) {
                Remove-MemberFromGroup -Group:$Group -Member:$_.ADSI;
            }
        }

        return $Local:RemovedUsers
    }

}

#endregion - Script Functions

#region - Fixup Groups

function Get-LocalUsers {
    Get-CimInstance Win32_UserAccount | Where-Object { $_.Disabled -eq $false }
}

function Get-LocalGroupMembers([Parameter(Mandatory)][String]$Group) {
    $Users = (Get-CimInstance Win32_Group -Filter "Name='$Group'" | Get-CimAssociatedInstance | Where-Object { $_.Disabled -eq $false })
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
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $MissingGroups = Get-LocalUserWithoutGroups

        if (($null -eq $MissingGroups) -or ($MissingGroups.Count -eq 0)) {
            return @()
        }

        foreach ($User in $MissingGroups) {
            switch ($NoModify) {
                $true { Invoke-Info "Would have added $($User.Name) to Users group" }
                $false { Add-LocalGroupMember -Group 'Users' -Member $User.Name | Out-Null }
            }
        }

        return $MissingGroups
    }

}

#endregion - Fixup Groups

function Get-ProcessedExceptions(
    [Parameter()]
    [String[]]$UserExceptions
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Exceptions; }

    process {
        function Split-NameAndDomain([String]$Name) {
            if ($Name.Contains('\')) {
                Invoke-Debug "Splitting [$Name] into domain and name";

                [String[]]$Split = $Name.Split('\');
                Invoke-Debug "Split [$($Split | ConvertTo-Json -Depth 1)]";

                if ($Split.Count -ne 2) {
                    Invoke-Error "Invalid format for exception [$Name]";
                    Invoke-FailedExit -ExitCode 1003;
                }

                return @{
                    Name = $Split[1];
                    Domain = $Split[0];
                };
            } else {
                Invoke-Debug "No domain specified for [$Name], using local domain";

                return @{
                    Name = $Name;
                    Domain = $env:COMPUTERNAME;
                };
            }
        }

        [HashTable[]]$Local:Exceptions = @();
        foreach ($Local:Exception in $UserExceptions) {
            if ($Local:Exception.Contains('=')) {
                Invoke-Debug "Possible scoped exception [$Local:Exception]";
                [String[]]$Local:Split = $Local:Exception.Split('=');
                [String]$Local:UserName = $Local:Split[0];

                if ($Local:Split.Count -eq 2) {
                    Invoke-Debug "Is a scoped exception";

                    [String[]]$Local:Computers = if ($Local:Split[1].Contains(',')) {
                        $Local:Split[1].Split(',');
                    } else {
                        @($Local:Split[1])
                    }

                    Invoke-Debug "Scoped exception for [$Local:UserName] covers computers [$($Local:Computers | ConvertTo-Json -Depth 1)]";

                    [HashTable]$Local:Exception = Split-NameAndDomain -Name $Local:UserName;
                    $Local:Exception | Add-Member -MemberType NoteProperty -Name Computers -Value $Local:Computers;

                    $Local:Exceptions += $Local:Exception;
                } else {
                    Invoke-Error "Invalid format for exception [$Local:Exception]";
                    Invoke-FailedExit -ExitCode 1003;
                }
            } else {
                Invoke-Debug "Exception for [$Local:Exception] is not scoped";

                [HashTable]$Local:Exception = Split-NameAndDomain -Name $Local:Exception;
                $Local:Exception | Add-Member -MemberType NoteProperty -Name Computers -Value @($env:COMPUTERNAME);

                $Local:Exceptions += $Local:Exception;
            }
        }

        return $Local:Exceptions;
    }
}

Import-Module $PSScriptRoot/../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    if ($NoModify) {
        Invoke-Info 'Running in WhatIf mode, no changes will be made.';
    } else {
        Invoke-EnsureAdministrator;
    }

    [ADSI]$Local:Group = Get-Group -Name 'Administrators';
    [HashTable]$Local:UserExceptions = Get-ProcessedExceptions -UserExceptions:$UserExceptions;
    [HashTable]$Local:LocalAdmins = Get-FilteredUsers -Group:$Local:Group -Exceptions:$Local:UserExceptions;

    $Local:RemovedAdmins = Remove-Admins -Group:$Local:Group -Users:$Local:LocalAdmins -Exceptions:$Local:UserExceptions;
    $Local:FixedUsers = Set-MissingGroup;

    if ($RemovedAdmins.Count -eq 0 -and $FixedUsers.Count -eq 0) {
        Invoke-Info 'No accounts modified'
    }
    else {
        foreach ($User in $FixedUsers) {
            Invoke-Info "Fixed user $($User.Name) by adding them to the Users group"
        }

        foreach ($User in $RemovedAdmins) {
            switch ($NoModify) {
                $true { Invoke-Info "Would have removed user $($User) from the administrators group" }
                $false { Invoke-Info "Removed user $($User) from the administrators group" }
            }
        }

        Exit 1001 # Exit code to indicate a change was made
    }
};

# AzureAD\CASFAdmin 'CASFAU\Domain Admins' CASFAU\casfadmin CASFAdmin TenciaAdmin CASFAU\zohoworkdrive=ZOHO-WORKDRIVE CASFAU\casfedi=CASF071