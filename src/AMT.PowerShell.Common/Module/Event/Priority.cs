// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

namespace AMT.PowerShell.Common.Module.Event;

/// <summary>Dispatch priority; matches the legacy PS Priority enum (ascending = Low first).</summary>
public enum Priority {
    Low = 0,
    Normal = 1,
    High = 2
}
