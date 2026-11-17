// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using AMT.PowerShell.Common.Commands.PSStyle;

namespace AMT.PowerShell.Common.Tests.Commands.PSStyle;

[TestFixture]
[NonParallelizable]
public sealed class PSStyleCommandTests {
    private static readonly string Escape = "\u001b";

    private static readonly Dictionary<ConsoleColor, string> ExpectedForegroundMap = new() {
        [ConsoleColor.Black] = $"{Escape}[30m",
        [ConsoleColor.DarkBlue] = $"{Escape}[34m",
        [ConsoleColor.DarkGreen] = $"{Escape}[32m",
        [ConsoleColor.DarkCyan] = $"{Escape}[36m",
        [ConsoleColor.DarkRed] = $"{Escape}[31m",
        [ConsoleColor.DarkMagenta] = $"{Escape}[35m",
        [ConsoleColor.DarkYellow] = $"{Escape}[33m",
        [ConsoleColor.Gray] = $"{Escape}[37m",
        [ConsoleColor.DarkGray] = $"{Escape}[90m",
        [ConsoleColor.Blue] = $"{Escape}[94m",
        [ConsoleColor.Green] = $"{Escape}[92m",
        [ConsoleColor.Cyan] = $"{Escape}[96m",
        [ConsoleColor.Red] = $"{Escape}[91m",
        [ConsoleColor.Magenta] = $"{Escape}[95m",
        [ConsoleColor.Yellow] = $"{Escape}[93m",
        [ConsoleColor.White] = $"{Escape}[97m"
    };

    [Test]
    public void GetConsoleColour_MapsAllConsoleColorsToAnsiForegroundSequences() {
        foreach (var pair in ExpectedForegroundMap) {
            var actual = Invoke("Get-ConsoleColour", new Dictionary<string, object?> {
                ["Colour"] = pair.Key
            }).Single().BaseObject as string;

            Assert.That(actual, Is.EqualTo(pair.Value), $"Unexpected escape for {pair.Key}");
        }
    }

    private static Collection<PSObject> Invoke(string commandName, IDictionary<string, object?>? parameters = null) {
        var initialSessionState = InitialSessionState.CreateDefault2();
        initialSessionState.Commands.Add(new SessionStateCmdletEntry("Get-ConsoleColour", typeof(GetConsoleColourCommand), null));

        using var runspace = RunspaceFactory.CreateRunspace(initialSessionState);
        runspace.Open();

        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddCommand(commandName);

        if (parameters is not null) {
            foreach (var parameter in parameters) {
                powerShell.AddParameter(parameter.Key, parameter.Value);
            }
        }

        var results = powerShell.Invoke();

        if (powerShell.HadErrors) {
            var errors = string.Join(
                Environment.NewLine,
                powerShell.Streams.Error.Select(error => error.ToString()));
            throw new AssertionException($"Command '{commandName}' failed:{Environment.NewLine}{errors}");
        }

        return results;
    }
}
