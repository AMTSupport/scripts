// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.UsersAndAccounts;

/// <summary>Gets the members of a local group via the ADSI WinNT provider.</summary>
/// <remarks>
/// Enumerates all principals that are direct members of the specified group.
/// Only works on Windows via the WinNT ADSI provider.
/// </remarks>
/// <example>
/// <code>Get-MembersOfGroup -Group (Get-Group -Name 'Administrators')</code>
/// Returns all members of the Administrators group.
/// </example>
/// <example>
/// <code>Get-Group -Name 'Administrators' | Get-MembersOfGroup</code>
/// Pipes the Administrators group and returns its members.
/// </example>
[Cmdlet(VerbsCommon.Get, "MembersOfGroup")]
[OutputType(typeof(AdsiPrincipal))]
public sealed class GetMembersOfGroupCommand : Cmdlet {
    /// <summary>The group whose members to enumerate; accepts an AdsiPrincipal or a group name string.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNull]
    public object? Group { get; set; }

    protected override void ProcessRecord() {
        try {
            var group = AdsiOperations.ResolveGroup(Group);
            WriteObject(AdsiOperations.GetMembers(group), enumerateCollection: true);
        } catch (AdsiResolutionException ex) {
            WriteError(AdsiErrors.InvalidArgument(ex.Message, ex.Target));
        } catch (PlatformNotSupportedException ex) {
            WriteError(AdsiErrors.PlatformNotSupported(ex.Message));
        }
    }
}
