// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

namespace AMT.PowerShell.Common.Commands.UsersAndAccounts;

/// <summary>
/// A group association resolved from the machine/domain group-user query
/// (mirrors the WMI Win32_Group object shape returned by the legacy path).
/// </summary>
public sealed class GroupObject {
    public GroupObject(string domain, string name, string path) {
        Domain = domain;
        Name = name;
        Path = path;
    }

    public string Domain { get; }

    public string Name { get; }

    public string Path { get; }
}
