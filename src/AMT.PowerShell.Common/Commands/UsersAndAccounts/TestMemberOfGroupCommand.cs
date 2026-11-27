// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.UsersAndAccounts;

/// <summary>Tests whether a user is a member of a local group via the ADSI WinNT provider.</summary>
/// <remarks>
/// Returns <see langword="true"/> when the user is a direct member of the group,
/// otherwise <see langword="false"/>.
/// Only works on Windows via the WinNT ADSI provider.
/// </remarks>
/// <example>
/// <code>Test-MemberOfGroup -Group (Get-Group -Name 'Administrators') -User 'localadmin'</code>
/// Returns $true if localadmin is a member of the Administrators group.
/// </example>
[Cmdlet(VerbsDiagnostic.Test, "MemberOfGroup")]
[OutputType(typeof(bool))]
public sealed class TestMemberOfGroupCommand : Cmdlet {
    /// <summary>The group to test membership against; accepts an AdsiPrincipal or a group name string.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNull]
    public object? Group { get; set; }

    /// <summary>The user to test; accepts an AdsiPrincipal or a user name string.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNull]
    public object? User { get; set; }

    protected override void ProcessRecord() {
        try {
            var group = AdsiOperations.ResolveGroup(Group);
            var user = AdsiOperations.ResolveUser(User);
            WriteObject(AdsiOperations.IsMember(group, user));
        } catch (AdsiResolutionException ex) {
            WriteError(AdsiErrors.InvalidArgument(ex.Message, ex.Target));
        } catch (PlatformNotSupportedException ex) {
            WriteError(AdsiErrors.PlatformNotSupported(ex.Message));
        }
    }
}
