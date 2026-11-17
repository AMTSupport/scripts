// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.UsersAndAccounts;

/// <summary>Gets local user accounts from the ADSI WinNT provider.</summary>
/// <remarks>
/// Returns all local users when Name is omitted, or a single user by name.
/// Only works on Windows via the WinNT ADSI provider.
/// </remarks>
/// <example>
/// <code>Get-User</code>
/// Returns every local user account.
/// </example>
/// <example>
/// <code>Get-User -Name 'localadmin'</code>
/// Returns the local user named localadmin.
/// </example>
[Cmdlet(VerbsCommon.Get, "User")]
[OutputType(typeof(AdsiPrincipal))]
public sealed class GetUserCommand : Cmdlet {
    /// <summary>The name of the user to retrieve; omit to return all local users.</summary>
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty]
    public string? Name { get; set; }

    protected override void ProcessRecord() {
        try {
            if (string.IsNullOrEmpty(Name)) {
                WriteObject(AdsiOperations.GetUsers(), enumerateCollection: true);
            } else {
                WriteObject(AdsiOperations.GetUser(Name!));
            }
        } catch (AdsiResolutionException ex) {
            WriteError(AdsiErrors.InvalidArgument(ex.Message, ex.Target));
        } catch (PlatformNotSupportedException ex) {
            WriteError(AdsiErrors.PlatformNotSupported(ex.Message));
        }
    }
}
