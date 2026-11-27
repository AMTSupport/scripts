// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;

namespace AMT.PowerShell.Common.Commands.UsersAndAccounts;

/// <summary>
/// Raised when a group/user input cannot be resolved to a principal.
/// </summary>
internal sealed class AdsiResolutionException : Exception {
    public AdsiResolutionException(string message, object? target = null)
        : base(message) {
        Target = target;
    }

    public object? Target { get; }
}
