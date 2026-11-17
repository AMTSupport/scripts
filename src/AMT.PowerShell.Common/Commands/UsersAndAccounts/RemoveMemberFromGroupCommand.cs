// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.UsersAndAccounts;

/// <summary>Removes a user from a local group via the ADSI WinNT provider.</summary>
/// <remarks>
/// Returns <see langword="true"/> when the user was removed, or <see langword="false"/> when
/// the user was not a member of the group.
/// Only works on Windows via the WinNT ADSI provider.
/// </remarks>
/// <example>
/// <code>Remove-MemberFromGroup -Group (Get-Group -Name 'Administrators') -Member 'localadmin'</code>
/// Removes the local user localadmin from the Administrators group.
/// </example>
[Cmdlet(VerbsCommon.Remove, "MemberFromGroup")]
[OutputType(typeof(bool))]
public sealed class RemoveMemberFromGroupCommand : Cmdlet {
    /// <summary>The group to remove the member from; accepts an AdsiPrincipal or a group name string.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNull]
    public object? Group { get; set; }

    /// <summary>The user to remove from the group; accepts an AdsiPrincipal or a user name string.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNull]
    public object? Member { get; set; }

    protected override void ProcessRecord() {
        try {
            var group = AdsiOperations.ResolveGroup(Group);
            var user = AdsiOperations.ResolveUser(Member);

            if (!AdsiOperations.IsMember(group, user)) {
                WriteVerbose($"User {user.Name} is not a member of group {group.Name}.");
                WriteObject(false);
                return;
            }

            WriteVerbose($"Removing user {user.Name} from group {group.Name}...");
            AdsiOperations.RemoveMember(group, user);
            WriteObject(true);
        } catch (AdsiResolutionException ex) {
            WriteError(AdsiErrors.InvalidArgument(ex.Message, ex.Target));
        } catch (PlatformNotSupportedException ex) {
            WriteError(AdsiErrors.PlatformNotSupported(ex.Message));
        }
    }
}
