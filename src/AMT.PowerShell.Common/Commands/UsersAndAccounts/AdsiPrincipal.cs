// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

namespace AMT.PowerShell.Common.Commands.UsersAndAccounts;

/// <summary>
/// A user or group principal resolved from the ADSI provider.
/// </summary>
public sealed class AdsiPrincipal {
    public AdsiPrincipal(string name, string schemaClassName, string path, string? parent = null) {
        Name = name;
        SchemaClassName = schemaClassName;
        Path = path;
        Parent = parent;
    }

    public string Name { get; }

    public string SchemaClassName { get; }

    public string Path { get; }

    public string? Parent { get; }
}
