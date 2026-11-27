// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.UsersAndAccounts;

/// <summary>Adds a user to a local group via the ADSI WinNT provider.</summary>
/// <remarks>
/// Returns <see langword="true"/> when the user was added, or <see langword="false"/> when
/// the user was already a member.
/// Only works on Windows via the WinNT ADSI provider.
/// </remarks>
/// <example>
/// <code>Add-MemberToGroup -Group (Get-Group -Name 'Administrators') -User 'localadmin'</code>
/// Adds the local user localadmin to the Administrators group.
/// </example>
[Cmdlet(VerbsCommon.Add, "MemberToGroup")]
[OutputType(typeof(bool))]
public sealed class AddMemberToGroupCommand : Cmdlet {
    /// <summary>The group to add the user to; accepts an AdsiPrincipal or a group name string.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNull]
    public object? Group { get; set; }

    /// <summary>The user to add to the group; accepts an AdsiPrincipal or a user name string.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNull]
    public object? User { get; set; }

    protected override void ProcessRecord() {
        try {
            var group = AdsiOperations.ResolveGroup(Group);
            var user = AdsiOperations.ResolveUser(User);

            if (AdsiOperations.IsMember(group, user)) {
                WriteVerbose($"User {user.Name} is already a member of group {group.Name}.");
                WriteObject(false);
                return;
            }

            WriteVerbose($"Adding user {user.Name} to group {group.Name}...");
            AdsiOperations.AddMember(group, user);
            WriteObject(true);
        } catch (AdsiResolutionException ex) {
            WriteError(AdsiErrors.InvalidArgument(ex.Message, ex.Target));
        } catch (PlatformNotSupportedException ex) {
            WriteError(AdsiErrors.PlatformNotSupported(ex.Message));
        }
    }
}
