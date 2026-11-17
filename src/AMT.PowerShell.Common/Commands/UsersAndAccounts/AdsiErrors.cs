// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.UsersAndAccounts;

internal static class AdsiErrors {
    private const string PlatformNotSupportedErrorId = "AMT.UsersAndAccounts.PlatformNotSupported";
    private const string InvalidArgumentErrorId = "AMT.UsersAndAccounts.InvalidArgument";

    internal static ErrorRecord PlatformNotSupported(string message) =>
        new(
            new PlatformNotSupportedException(message),
            PlatformNotSupportedErrorId,
            ErrorCategory.NotImplemented,
            targetObject: null);

    internal static ErrorRecord InvalidArgument(string message, object? target) =>
        new(
            new ArgumentException(message),
            InvalidArgumentErrorId,
            ErrorCategory.InvalidArgument,
            target);
}
