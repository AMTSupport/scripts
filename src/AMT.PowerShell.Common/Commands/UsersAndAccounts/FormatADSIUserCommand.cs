// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.UsersAndAccounts;

/// <summary>Formats one or more ADSI user principals as hashtables containing Name and Domain.</summary>
/// <remarks>
/// Each input AdsiPrincipal must have a SchemaClassName of "User".
/// The returned hashtable contains the keys "Name" and "Domain" split from the ADSI path.
/// </remarks>
/// <example>
/// <code>Get-User | Format-ADSIUser</code>
/// Formats all local users as Name/Domain hashtables.
/// </example>
/// <example>
/// <code>Format-ADSIUser -User (Get-User -Name 'localadmin')</code>
/// Formats the localadmin user as a Name/Domain hashtable.
/// </example>
[Cmdlet(VerbsCommon.Format, "ADSIUser")]
[OutputType(typeof(Hashtable))]
public sealed class FormatADSIUserCommand : Cmdlet {
    /// <summary>One or more ADSI user principals to format; must have SchemaClassName "User".</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNull]
    public AdsiPrincipal[] User { get; set; } = Array.Empty<AdsiPrincipal>();

    protected override void ProcessRecord() {
        foreach (var principal in User) {
            if (!string.Equals(principal.SchemaClassName, "User", StringComparison.Ordinal)) {
                WriteError(AdsiErrors.InvalidArgument(
                    "The supplied object is not a User.",
                    principal));
                return;
            }
        }

        foreach (var principal in User) {
            WriteObject(Format(principal));
        }
    }

    private static Hashtable Format(AdsiPrincipal user) {
        var (domain, name) = AdsiOperations.SplitAccountPath(user.Path);

        return new Hashtable {
            { "Name", name },
            { "Domain", domain },
        };
    }
}
