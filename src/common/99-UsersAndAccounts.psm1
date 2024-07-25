#Requires -Version 5.1

#region - Caching

$Script:InitialisedAllGroups = $False;
$Script:CachedGroups = @{};
$Script:InitialisedAllUsers = $False;
$Script:CachedUsers = @{};

#endregion

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
    begin {
        Enter-Scope -ArgumentFormatter @{
            InputObject = { "$($_.Name) of type $($_.SchemaClassName)" };
        };
    }
    end { Exit-Scope -ReturnValue $Local:Value; }

    process {
        if ($InputObject -is [String] -and $InputObject -eq '') {
            Write-Error 'An empty string was supplied, this is not a valid object.' -Category InvalidArgument;
        }

        if ($InputObject -is [String]) {
            [ADSI]$Local:Value = $GetByName.InvokeReturnAsIs();
        }
        elseif ($InputObject.SchemaClassName -ne $SchemaClassName) {
            Write-Host "$($InputObject.SchemaClassName)"
            Write-Error "The supplied object is not a $SchemaClassName." -TargetObject $InputObject -Category InvalidArgument;
        }
        else {
            [ADSI]$Local:Value = $InputObject;
        }

        return $Local:Value;
    }
}

function Get-GroupByInputOrName([Object]$InputObject) {
    return Get-ObjectByInputOrName -InputObject $InputObject -SchemaClassName 'Group' -GetByName { Get-Group $InputObject; };
}

function Get-UserByInputOrName([Object]$InputObject) {
    return Get-ObjectByInputOrName -InputObject $InputObject -SchemaClassName 'User' -GetByName {
        if (-not ($InputObject.Contains('/'))) {
            $InputObject = "$env:COMPUTERNAME/$InputObject";
        }

        Get-User $InputObject;
    };
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
    ```
    Get-Group -Name 'Administrators';
    ```

.EXAMPLE
    This will return all groups on the local machine.
    ```
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
            Invoke-Debug 'Getting all groups...'
            if (-not $Script:InitialisedAllGroups) {
                Invoke-Debug 'Initialising all groups...';
                $Script:CachedGroups;
                [ADSI]$Local:Groups = [ADSI]"WinNT://$env:COMPUTERNAME";
                $Local:Groups.Children | Where-Object { $_.SchemaClassName -eq 'Group' } | ForEach-Object { $Script:CachedGroups[$_.Name] = $_; };
                $Script:InitialisedAllGroups = $True;
            }

            $Local:Value = $Script:CachedGroups.Values;
        }
        else {
            Invoke-Debug "Getting group $Name...";
            if (-not $Script:InitialisedAllGroups -or -not $Script:CachedGroups[$Name]) {
                [ADSI]$Local:Group = [ADSI]"WinNT://$env:COMPUTERNAME/$Name,group";
                $Script:CachedGroups[$Name] = $Local:Group;
            }

            $Local:Value = $Script:CachedGroups[$Name];
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
    ```
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
            }
            else {
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

.PARAMETER User
    The user to test if they are a member of the group.

.EXAMPLE
    This will test if the user localadmin is a member of the Administrators group.
    ```
    Test-MemberOfGroup -Group (Get-Group -Name 'Administrators') -User 'localadmin';
    ```

.NOTES
    This function is designed to work with the ADSI provider for the local machine.
    It will not work with remote machines or other providers.
#>
function Test-MemberOfGroup(
    [Parameter(Mandatory)]
    [Object]$Group,

    [Parameter(Mandatory)]
    [Object]$User
) {
    begin {
        Enter-Scope -ArgumentFormatter @{
            Group = { $_.Name + $_.SchemaClassName };
            User  = { $_.Name + $_.SchemaClassName };
        };
    }
    end { Exit-Scope -ReturnValue $Local:User; }

    process {
        Invoke-Debug 'Getting group';
        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject $Group;
        Invoke-Debug 'Getting user';
        [ADSI]$Local:User = Get-UserByInputOrName -InputObject $User;

        Invoke-Debug 'Testing if user is a member of group...';
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

.PARAMETER User
    The user to add to the group.

.EXAMPLE
    This will add the user localadmin to the Administrators group.
    ```
    Add-MemberToGroup -Group (Get-Group -Name 'Administrators') -User 'localadmin';
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
    [Object]$User
) {
    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        [ADSI]$Local:Group = Get-GroupByInputOrName -InputObject $Group;
        [ADSI]$Local:User = Get-UserByInputOrName -InputObject $User;

        if (Test-MemberOfGroup -Group $Local:Group -User $Local:User) {
            Invoke-Verbose "User $User is already a member of group $Group.";
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

        if (-not (Test-MemberOfGroup -Group $Local:Group -User $Local:User)) {
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

# FIXME
function Get-User(
    [Parameter(HelpMessage = 'The name of the user to retrieve, if not specified all users will be returned.')]
    [ValidateNotNullOrEmpty()]
    [String]$Name
) {
    begin { Enter-Scope; }
    # end { Exit-Scope -ReturnValue $Local:Value; }

    process {
        if (-not $Name) {
            if (-not $Script:InitialisedAllUsers) {
                $Script:CachedUsers = @{};
                [ADSI]$Local:Users = [ADSI]"WinNT://$env:COMPUTERNAME";
                $Local:Users.Children | Where-Object { $_.SchemaClassName -eq 'User' } | ForEach-Object { $Script:CachedUsers[$_.Name] = $_; };
                $Script:InitialisedAllUsers = $True;
            }

            $Local:Value = $Script:CachedUsers;
        }
        else {
            $null = Get-User;
            if (-not $Script:InitialisedAllUsers -or -not $Script:CachedUsers[$Name]) {
                $Script:CachedUsers = @{};
                [ADSI]$Local:User = [ADSI]"WinNT://$Name,user";
                $Script:CachedUsers[$Name] = $Local:User;
            }

            $Local:Value = $Script:CachedUsers[$Name];
            $Global:CachedUsers = $Script:CachedUsers;
        }
        return $Local:Value;
    }
}

function Get-UserGroups(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [Object]$User
) {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:UserGroups; }

    process {
        [ADSI]$Local:User = Get-UserByInputOrName -InputObject $User;
        [String]$Local:Domain = $Local:User.Path.Split('/')[0];
        [String]$Local:Username = $Local:User.Path.Split('/')[1];
        Get-WmiObject -Class Win32_GroupUser `
        | Where-Object { $_.PartComponent -match "Domain=""$Domain"",Name=""$Username""" } `
        | ForEach-Object { [WMI]$_.GroupComponent };

        # [ADSI]$Local:User = Get-UserByInputOrName -InputObject $User;
        # [ADSI[]]$Local:Groups = Get-Group;

        # [ADSI[]]$Local:UserGroups = @();
        # foreach ($Local:Group in $Local:Groups) {
        #     if (Test-MemberOfGroup -Group $Local:Group -User $Local:User) {
        #         $Local:UserGroups += $Local:Group;
        #     }
        # }

        return $Local:UserGroups;
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
        }
        else {
            [String]$Local:Path = $User.Path.Substring(8); # Remove the WinNT:// prefix
            [String[]]$Local:PathParts = $Local:Path.Split('/');

            # The username is always last followed by the domain.
            [HashTable]$Local:Value = @{
                Name   = $Local:PathParts[$Local:PathParts.Count - 1]
                Domain = $Local:PathParts[$Local:PathParts.Count - 2]
            };

            return $Local:Value;
        }

    }
}

#endregion

Export-ModuleMember -Function Get-User, Get-UserGroups, Get-Group, Get-MembersOfGroup, Test-MemberOfGroup, Add-MemberToGroup, Remove-MemberFromGroup, Format-ADSIUser, Get-GroupByInputOrName, Get-UserByInputOrName;
