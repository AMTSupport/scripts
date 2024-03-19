#Requires -Version 5.1

#region - Private Functions

function Local:Get-ObjectByInputOrName(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ $_ -is [String] -or $_ -is [ADSI] })]
    [Object]$InputObject,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String]$SchemaClassName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ScriptBlock]$GetByName
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Value; }

    process {
        if ($InputObject -is [String]) {
            [ADSI]$Local:Value = $GetByName.InvokeReturnAsIs();
        } elseif ($InputObject.SchemaClassName -ne $SchemaClassName) {
            Write-Error "The supplied object is not a $SchemaClassName." -TargetObject $InputObject -Category InvalidArgument;
        } else {
            [ADSI]$Local:Value = $InputObject;
        }

        return $Local:Value;
    }
}

function Local:Get-GroupByInputOrName([Object]$InputObject) {
    return Get-ObjectByInputOrName -InputObject $InputObject -SchemaClassName 'Group' -GetByName { Get-Group $Using:InputObject; };
}

function Local:Get-UserByInputOrName([Object]$InputObject) {
    return Get-ObjectByInputOrName -InputObject $InputObject -SchemaClassName 'User' -GetByName { Get-User $Using:InputObject; };
}

#endregion

#region - Group Functions

<#
.SYNOPSIS
    Gets the groups on the local machine, returning a list of ADSI objects.

.DESCRIPTION
    This function will return a list of groups on the local machine.
    If a name is specified then only the group with that name will be returned.

.OUTPUTS
    [ADSI[]] - A list of ADSI objects representing the groups on the local machine.

.PARAMETER Name
    The name of the group to retrieve, if not specified all groups will be returned.

.EXAMPLE
    This will return the Administrators group.
    ```powershell
    Get-Group -Name 'Administrators';
    ```

.EXAMPLE
    This will return all groups on the local machine.
    ```powershell
    Get-Group;
    ```

.NOTES
    This function is designed to work with the ADSI provider for the local machine.
    It will not work with remote machines or other providers.
#>
function Get-Group(
    [Parameter(HelpMessage = 'The name of the group to retrieve, if not specified all groups will be returned.')]
    [ValidateNotNullOrEmpty()]
    [String]$Name
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Value; }

    process {
        if (-not $Name) {
            [ADSI]$Local:Groups = [ADSI]"WinNT://$env:COMPUTERNAME";
            $Local:Value = $Local:Groups.Children | Where-Object { $_.SchemaClassName -eq 'Group' };
        }
        else {
            [ADSI]$Local:Value = [ADSI]"WinNT://$env:COMPUTERNAME/$Name,group";
        }

        return $Local:Value;
    }
}

<#
.SYNOPSIS
    Gets the members of a group.

.DESCRIPTION
    This function will return a list of members of a group.
    If a group is specified then only the members of that group will be returned.

.OUTPUTS
    [ADSI[]] - A list of ADSI objects representing the members of the group.

.PARAMETER Group
    The group to retrieve the members of.

.EXAMPLE
    This will return the members of the Administrators group.
    ```powershell
    Get-MembersOfGroup -Group (Get-Group -Name 'Administrators');
    ```

.NOTES
    This function is designed to work with the ADSI provider for the local machine.
    It will not work with remote machines or other providers.
#>
function Get-MembersOfGroup(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [Object]$Group
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Members; }

    process {
        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject:$Group;

        $Group.Invoke('Members') `
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

<#
.SYNOPSIS
    Tests if a user is a member of a group.

.DESCRIPTION
    This function will test if a user is a member of a group.

.OUTPUTS
    [Boolean] - $True if the user is a member of the group, otherwise $False.

.PARAMETER Group
    The group to test if the user is a member of.

.PARAMETER Username
    The username to test if they are a member of the group.

.EXAMPLE
    This will test if the user localadmin is a member of the Administrators group.
    ```powershell
    Test-MemberOfGroup -Group (Get-Group -Name 'Administrators') -Username 'localadmin';
    ```

.NOTES
    This function is designed to work with the ADSI provider for the local machine.
    It will not work with remote machines or other providers.
#>
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

        return $Local:Group.Invoke('IsMember', $Local:User.Path);
    }
}

<#
.SYNOPSIS
    Adds a user to a group.

.DESCRIPTION
    This function will add a user to a group.

.OUTPUTS
    [Boolean] - $True if the user was added to the group, otherwise $False.

.PARAMETER Group
    The group to add the user to.

.PARAMETER Username
    The username to add to the group.

.EXAMPLE
    This will add the user localadmin to the Administrators group.
    ```powershell
    Add-MemberToGroup -Group (Get-Group -Name 'Administrators') -Username 'localadmin';
    ```

.NOTES
    This function is designed to work with the ADSI provider for the local machine.
    It will not work with remote machines or other providers.
#>
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
        $Local:Group.Invoke('Add', $Local:User.Path);

        return $True;
    }
}

<#
.SYNOPSIS
    Removes a user from a group.

.DESCRIPTION
    This function will remove a user from a group.

.OUTPUTS

#>
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
        $Local:Group.Invoke('Remove', $Local:User.Path);

        return $True;
    }
}

#endregion

#region - User Functions

function Get-User(
    [Parameter(HelpMessage = 'The name of the user to retrieve, if not specified all users will be returned.')]
    [ValidateNotNullOrEmpty()]
    [String]$Name
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Value; }

    process {
        if (-not $Name) {
            [ADSI]$Local:Users = [ADSI]"WinNT://$env:COMPUTERNAME";
            $Local:Value = $Local:Users.Children | Where-Object { $_.SchemaClassName -eq 'User' };
        }
        else {
            [ADSI]$Local:Value = [ADSI]"WinNT://$env:COMPUTERNAME/$Name,user";
        }

        return $Local:Value;
    }
}

#endregion

#region - Formatting Functions

function Format-ADSIUser(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ $_ | ForEach-Object { $_.SchemaClassName -eq 'User' } })]
    [ADSI[]]$User
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Value; }

    process {
        if ($User -is [Array] -and $User.Count -gt 1) {
            $Local:Value = $User | ForEach-Object {
                Format-ADSIUser -User $_;
            };

            return $Local:Value;
        } else {
            [String]$Local:Path = $User.Path.Substring(8); # Remove the WinNT:// prefix
            [String[]]$Local:PathParts = $Local:Path.Split('/');

            # The username is always last followed by the domain.
            [HashTable]$Local:Value = @{
                Name = $Local:PathParts[$Local:PathParts.Count - 1]
                Domain = $Local:PathParts[$Local:PathParts.Count - 2]
            };

            return $Local:Value;
        }

    }
}

#endregion

Export-ModuleMember -Function Get-User, Get-Group, Get-MembersOfGroup, Test-MemberOfGroup, Add-MemberToGroup, Remove-MemberFromGroup, Format-ADSIUser;
