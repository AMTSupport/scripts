// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;

namespace Compiler.Analyser;

// Runtime definition of the analyser suppression attribute. The compiler keeps
// its own copy; compiled scripts only load this module, so the type must exist
// here for scripts that declare the attribute.
[AttributeUsage(AttributeTargets.All, AllowMultiple = true, Inherited = false)]
public sealed class SuppressAnalyserAttribute : Attribute {
    public readonly string CheckType;
    public readonly object? Data;
    public string? Justification;

    public SuppressAnalyserAttribute(string checkType, object? data) {
        this.CheckType = checkType;
        this.Data = data;
    }
}
