// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.UsersAndAccounts;

/// <summary>Gets local group accounts from the ADSI WinNT provider.</summary>
/// <remarks>
/// Returns all local groups when Name is omitted, or a single group by name.
/// Only works on Windows via the WinNT ADSI provider.
/// </remarks>
/// <example>
/// <code>Get-Group</code>
/// Returns every local group account.
/// </example>
/// <example>
/// <code>Get-Group -Name 'Administrators'</code>
/// Returns the local group named Administrators.
/// </example>
[Cmdlet(VerbsCommon.Get, "Group")]
[OutputType(typeof(AdsiPrincipal))]
public sealed class GetGroupCommand : Cmdlet {
    /// <summary>The name of the group to retrieve; omit to return all local groups.</summary>
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty]
    public string? Name { get; set; }

    protected override void ProcessRecord() {
        try {
            if (string.IsNullOrEmpty(Name)) {
                WriteObject(AdsiOperations.GetGroups(), enumerateCollection: true);
            } else {
                WriteObject(AdsiOperations.GetGroup(Name!));
            }
        } catch (AdsiResolutionException ex) {
            WriteError(AdsiErrors.InvalidArgument(ex.Message, ex.Target));
        } catch (PlatformNotSupportedException ex) {
            WriteError(AdsiErrors.PlatformNotSupported(ex.Message));
        }
    }
}
