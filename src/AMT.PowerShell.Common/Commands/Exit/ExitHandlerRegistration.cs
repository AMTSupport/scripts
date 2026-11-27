// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Exit;

public sealed class ExitHandlerRegistration {
    internal ExitHandlerRegistration(string name, ScriptBlock script, bool onlyFailure) {
        this.Name = name;
        this.Script = script;
        this.OnlyFailure = onlyFailure;
    }

    public string Name { get; }

    public bool OnlyFailure { get; }

    public ScriptBlock Script { get; }
}
