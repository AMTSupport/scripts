function Local:Get-GroupByInputOrName(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ $_ -is [String] -or $_ -is [ADSI] })]
    [Object]$InputObject
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Group; }

    process {
        if ($InputObject -is [String]) {
            [ADSI]$Local:Group = Get-Group -Name $InputObject;
        } elseif ($InputObject.SchemaClassName -ne 'Group') {
            Write-Error 'The supplied object is not a group.' -TargetObject $InputObject -Category InvalidArgument;
        } else {
            [ADSI]$Local:Group = $InputObject;
        }

        return $Local:Group;
    }
}

function Local:Get-UserByInputOrName(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ $_ -is [String] -or $_ -is [ADSI] })]
    [Object]$InputObject
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:User; }

    process {
        if ($InputObject -is [String]) {
            [ADSI]$Local:User = Get-User -Name $InputObject;
        } elseif ($InputObject.SchemaClassName -ne 'User') {
            Write-Error 'The supplied object is not a user.' -TargetObject $InputObject -Category InvalidArgument;
        } else {
            [ADSI]$Local:User = $InputObject;
        }

        return $Local:User;
    }
}

function Get-FormattedUser(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ $_.SchemaClassName -eq 'User' })]
    [ADSI]$User
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:FormattedUser; }

    process {
        [String]$Local:Path = $User.Path.Substring(8); # Remove the WinNT:// prefix
        [String[]]$Local:PathParts = $Local:Path.Split('/');

        # The username is always last followed by the domain.
        [HashTable]$Local:FormattedUser = @{
            Name = $Local:PathParts[$Local:PathParts.Count - 1]
            Domain = $Local:PathParts[$Local:PathParts.Count - 2]
        };

        return $Local:FormattedUser;
    }
}

function Get-FormattedUsers(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ADSI[]]$Users
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:FormattedUsers; }

    process {
        $Local:FormattedUsers = $Users | ForEach-Object {
            Get-FormattedUser -User $_;
        };

        return $Local:FormattedUsers;
    }
}

function Test-MemberOfGroup(
    [Parameter(Mandatory)]
    [Object]$Group,

    [Parameter(Mandatory)]
    [Object]$Username
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:User; }

    process {
        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject $Group;
        [ADSI]$Local:User = Get-UserByInputOrName -InputObject $Username;

        return $Local:Group.Invoke("IsMember", $Local:User.Path);
    }
}

function Get-Group(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$Name
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Group; }

    process {
        [ADSI]$Local:Group = [ADSI]"WinNT://$env:COMPUTERNAME/$Name,group";
        return $Local:Group
    }
}

function Get-Groups {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Groups; }

    process {
        $Local:Groups = [ADSI]"WinNT://$env:COMPUTERNAME";
        $Local:Groups.Children | Where-Object { $_.SchemaClassName -eq 'Group' };
    }
}

<#
.SYNOPSIS
    Gets the members of a group, returning a list of psobjects with their name and domain.
#>
function Get-GroupMembers(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [Object]$Group
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Members; }

    process {
        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject $Group;

        $Group.Invoke("Members") `
            | ForEach-Object { [ADSI]$_ } `
            | Where-Object {
                if ($_.Parent.Length -gt 8) {
                    $_.Parent.Substring(8) -ne 'NT AUTHORITY'
                } else {
                    # This is a in-built user, skip it.
                    $False
                }
            };
    }
}

function Add-MemberToGroup(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [Object]$Group,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [Object]$Username
) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject $Group;
        [ADSI]$Local:User = Get-UserByInputOrName -InputObject $Username;

        if (Test-MemberOfGroup -Group $Local:Group -Username $Local:User) {
            Invoke-Verbose "User $Username is already a member of group $Group.";
            return $False;
        }

        Invoke-Verbose "Adding user $Name to group $Group...";
        $Local:Group.Invoke("Add", $Local:User.Path);

        return $True;
    }
}

function Remove-MemberFromGroup(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [Object]$Group,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [Object]$Member
) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject $Group;
        [ADSI]$Local:User = Get-UserByInputOrName -InputObject $Member;

        if (-not (Test-MemberOfGroup -Group $Local:Group -Username $Local:User)) {
            Invoke-Verbose "User $Member is not a member of group $Group.";
            return $False;
        }

        Invoke-Verbose "Removing user $Name from group $Group...";
        $Local:Group.Invoke("Remove", $Local:User.Path);

        return $True;
    }
}

Export-ModuleMember -Function Add-MemberToGroup, Get-FormattedUser, Get-FormattedUsers, Get-Group, Get-Groups, Get-GroupMembers, Get-UserByInputOrName, Remove-MemberFromGroup, Test-MemberOfGroup;
