// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.UsersAndAccounts;

/// <summary>Resolves a local group from an AdsiPrincipal object or a name string.</summary>
/// <remarks>
/// Accepts either an already-resolved AdsiPrincipal or a plain string group name.
/// Useful as a normalisation step in pipeline-driven scripts.
/// Only works on Windows via the WinNT ADSI provider.
/// </remarks>
/// <example>
/// <code>Get-GroupByInputOrName -InputObject 'Administrators'</code>
/// Resolves the Administrators group by name.
/// </example>
/// <example>
/// <code>Get-GroupByInputOrName -InputObject (Get-Group -Name 'Administrators')</code>
/// Returns the already-resolved AdsiPrincipal unchanged.
/// </example>
[Cmdlet(VerbsCommon.Get, "GroupByInputOrName")]
[OutputType(typeof(AdsiPrincipal))]
public sealed class GetGroupByInputOrNameCommand : Cmdlet {
    /// <summary>An AdsiPrincipal group object or a group name string to resolve.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNull]
    public object? InputObject { get; set; }

    protected override void ProcessRecord() {
        try {
            WriteObject(AdsiOperations.ResolveGroup(InputObject));
        } catch (AdsiResolutionException ex) {
            WriteError(AdsiErrors.InvalidArgument(ex.Message, ex.Target));
        } catch (PlatformNotSupportedException ex) {
            WriteError(AdsiErrors.PlatformNotSupported(ex.Message));
        }
    }
}
