// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections.Generic;

namespace AMT.PowerShell.Common.Commands.UsersAndAccounts;

internal interface IAdsiProvider {
    bool IsSupported { get; }

    IReadOnlyList<AdsiPrincipal> GetGroups();

    AdsiPrincipal GetGroup(string name);

    IReadOnlyList<AdsiPrincipal> GetUsers();

    AdsiPrincipal GetUser(string name);

    IReadOnlyList<AdsiPrincipal> GetMembers(AdsiPrincipal group);

    bool IsMember(AdsiPrincipal group, AdsiPrincipal user);

    void AddMember(AdsiPrincipal group, AdsiPrincipal user);

    void RemoveMember(AdsiPrincipal group, AdsiPrincipal user);

    IReadOnlyList<GroupObject> GetUserGroups(AdsiPrincipal user);
}
