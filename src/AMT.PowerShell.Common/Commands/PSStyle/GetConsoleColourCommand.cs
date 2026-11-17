// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.PSStyle;

/// <summary>Returns the PSStyle ANSI foreground escape sequence for a given <see cref="ConsoleColor"/> value.</summary>
/// <remarks>
/// Maps <see cref="ConsoleColor"/> enum members to the corresponding <c>$PSStyle.Foreground.*</c> string
/// so callers can embed colour sequences in strings without depending on the PSStyle variable directly.
/// </remarks>
/// <example>
/// <code>$red = Get-ConsoleColour -Colour Red</code>
/// Returns the ANSI foreground escape sequence for red.
/// </example>
[Cmdlet(VerbsCommon.Get, "ConsoleColour")]
[OutputType(typeof(string))]
public sealed class GetConsoleColourCommand : Cmdlet {
    /// <summary>The <see cref="ConsoleColor"/> value to map to a PSStyle foreground sequence.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public ConsoleColor Colour { get; set; }

    protected override void ProcessRecord() =>
        this.WriteObject(PSStyleColors.MapForegroundColor(this.Colour));
}
