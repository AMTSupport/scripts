// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Security;

namespace AMT.PowerShell.Common.Commands.Connection;

// A connectable service's operations. Production definitions delegate to the
// external Graph/Exchange cmdlets; tests replace them with deterministic fakes.
internal sealed class ServiceDefinition {
    internal ServiceDefinition(
        string name,
        Func<string?> context,
        Action<string[]?, SecureString?> connect,
        Action disconnect,
        Func<string[]?, bool?>? isValid = null,
        bool matchable = true) {
        this.Name = name;
        this.Context = context;
        this.Connect = connect;
        this.Disconnect = disconnect;
        this.IsValid = isValid;
        this.Matchable = matchable;
    }

    internal string Name { get; }

    internal bool Matchable { get; }

    internal Func<string?> Context { get; }

    internal Action<string[]?, SecureString?> Connect { get; }

    internal Action Disconnect { get; }

    internal Func<string[]?, bool?>? IsValid { get; }
}
