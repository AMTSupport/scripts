// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.UsersAndAccounts;

/// <summary>Gets the groups that a local user belongs to via the ADSI WinNT provider.</summary>
/// <remarks>
/// Returns one GroupObject per group the user is a direct member of.
/// Only works on Windows via the WinNT ADSI provider.
/// </remarks>
/// <example>
/// <code>Get-UserGroups -User 'localadmin'</code>
/// Returns all groups the local user localadmin belongs to.
/// </example>
/// <example>
/// <code>Get-User -Name 'localadmin' | Get-UserGroups</code>
/// Pipes the localadmin user and returns its group memberships.
/// </example>
[Cmdlet(VerbsCommon.Get, "UserGroups")]
[OutputType(typeof(GroupObject))]
public sealed class GetUserGroupsCommand : Cmdlet {
    /// <summary>The user whose group memberships to enumerate; accepts an AdsiPrincipal or a user name string.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNull]
    public object? User { get; set; }

    protected override void ProcessRecord() {
        try {
            var user = AdsiOperations.ResolveUser(User);
            WriteObject(AdsiOperations.GetUserGroups(user), enumerateCollection: true);
        } catch (AdsiResolutionException ex) {
            WriteError(AdsiErrors.InvalidArgument(ex.Message, ex.Target));
        } catch (PlatformNotSupportedException ex) {
            WriteError(AdsiErrors.PlatformNotSupported(ex.Message));
        }
    }
}
