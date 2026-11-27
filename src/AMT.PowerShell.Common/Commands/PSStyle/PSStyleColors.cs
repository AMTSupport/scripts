// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;

namespace AMT.PowerShell.Common.Commands.PSStyle;

internal static class PSStyleColors {
    private const string Escape = "\u001b";

    // Indexed by the ConsoleColor enum value; parity with the legacy
    // PSStyle.psm1 ForegroundColorMap.
    private static readonly string[] ForegroundMap = {
        $"{Escape}[30m", // Black
        $"{Escape}[34m", // DarkBlue
        $"{Escape}[32m", // DarkGreen
        $"{Escape}[36m", // DarkCyan
        $"{Escape}[31m", // DarkRed
        $"{Escape}[35m", // DarkMagenta
        $"{Escape}[33m", // DarkYellow
        $"{Escape}[37m", // Gray
        $"{Escape}[90m", // DarkGray
        $"{Escape}[94m", // Blue
        $"{Escape}[92m", // Green
        $"{Escape}[96m", // Cyan
        $"{Escape}[91m", // Red
        $"{Escape}[95m", // Magenta
        $"{Escape}[93m", // Yellow
        $"{Escape}[97m"  // White
    };

    internal static string MapForegroundColor(ConsoleColor color) {
        var index = (int)color;
        if (index < 0 || index >= ForegroundMap.Length) {
            throw new ArgumentOutOfRangeException(nameof(color), color, $"Color ({color}) out of range.");
        }

        return ForegroundMap[index];
    }
}
