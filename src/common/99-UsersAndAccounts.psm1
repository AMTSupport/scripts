function Local:Get-GroupByInputOrName(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ $_ -is [String] -or $_ -is [ADSI] })]
    [Object]$InputObject
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation $Local:Group; }

    process {
        if ($Input -is [String]) {
            [ADSI]$Local:Group = Get-Group -Name $InputObject;
        } elseif ($Input.SchemaClassName -ne 'Group') {
            throw "The supplied object is not a group.";
        } else {
            [ADSI]$Local:Group = $InputObject;
        }
    }
}

function Local:Get-UserByInputOrName(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ $_ -is [String] -or $_ -is [ADSI] })]
    [Object]$InputObject
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation $Local:User; }

    process {
        if ($Input -is [String]) {
            [ADSI]$Local:User = Get-User -Name $InputObject;
        } elseif ($Input.SchemaClassName -ne 'User') {
            throw "The supplied object is not a user.";
        } else {
            [ADSI]$Local:User = $InputObject;
        }
    }
}

function Get-FormattedUsers(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ADSI[]]$Users
) {
    return $Users | ForEach-Object {
        $Local:Path = $_.Path.Substring(8); # Remove the WinNT:// prefix
        $Local:PathParts = $Local:Path.Split('/');

        # The username is always last followed by the domain.
        [PSCustomObject]@{
            Name = $Local:PathParts[$Local:PathParts.Count - 1]
            Domain = $Local:PathParts[$Local:PathParts.Count - 2]
        };
    };
}

function Test-MemberOfGroup(
    [Parameter(Mandatory)]
    [Object]$Group,

    [Parameter(Mandatory)]
    [Object]$Username
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation $Local:User; }

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
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation $Local:Group; }

    process {
        [ADSI]$Local:Group = [ADSI]"WinNT://$env:COMPUTERNAME/$Name,group";
        return $Local:Group
    }
}

<#
.SYNOPSIS
    Gets the members of a group, returning a list of psobjects with their name and domain.
#>
function Get-GroupMembers(
    [Parameter(Mandatory)]
    [Object]$Group
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation $Local:Members; }

    process {
        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject $Group;

        $Group.Invoke("Members") `
            | ForEach-Object { [ADSI]$_ } `
            | Where-Object {
                $Local:Parent = $_.Parent.Substring(8); # Remove the WinNT:// prefix
                $Local:Parent -ne 'NT AUTHORITY'
            };
    }
}

function Add-MemberToGroup(
    [Parameter(Mandatory)]
    [Object]$Group,

    [Parameter(Mandatory)]
    [Object]$Username
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

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
    [Object]$Group,

    [Parameter(Mandatory)]
    [Object]$Username
) {
    begin { Enter-Scope -Invocation $MyInvocation; }
    end { Exit-Scope -Invocation $MyInvocation; }

    process {
        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject $Group;
        [ADSI]$Local:User = Get-UserByInputOrName -InputObject $Username;

        if (-not (Test-MemberOfGroup -Group $Local:Group -Username $Local:User)) {
            Invoke-Verbose "User $Username is not a member of group $Group.";
            return $False;
        }

        Invoke-Verbose "Removing user $Name from group $Group...";
        $Local:Group.Invoke("Remove", $Local:User.Path);

        return $True;
    }
}

Export-ModuleMember -Function Add-MemberToGroup, Get-FormattedUsers, Get-Group, Get-GroupMembers, Get-UserByInputOrName, Remove-MemberFromGroup, Test-MemberOfGroup;