// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

// Required for Analyser.psm1 import
#pragma warning disable IDE0240
#nullable enable
#pragma warning restore IDE0240

// Required for Analyser.psm1 import
#pragma warning disable IDE0005
using System;
#pragma warning restore IDE0005

using System.Diagnostics.CodeAnalysis;

namespace Compiler.Analyser;

public record Suppression(
    [NotNull] Type Type,
    [AllowNull] object? Data,
    [AllowNull] string? Justification
) {
    public override int GetHashCode() => HashCode.Combine(this.Type, this.Data, this.Justification);
    public override string ToString() => $"[{this.Type.Name}] {this.Justification} ({this.Data})";
}

[AttributeUsage(AttributeTargets.All, AllowMultiple = true, Inherited = false)]
public sealed class SuppressAnalyserAttribute(string checkType, object? data) : Attribute {
    public readonly string CheckType = checkType;
    public readonly object? Data = data;
    public string? Justification { get; set; }

    /// <summary>
    /// Gets the suppression details for the specified rule.
    /// </summary>
    /// <returns>A Suppression object representing the rule suppression.</returns>
    /// <exception cref="ArgumentException">Thrown if the checkType is not a valid rule name.</exception>
    [return: NotNull]
    public Suppression GetSuppression() {
        var assemblyName = "Compiler.Analyser.Rules." + this.CheckType;
        var type = Type.GetType(assemblyName, false, true) ?? throw new ArgumentException($"Could not find rule for suppression {this.CheckType}");
        return new Suppression(type, this.Data, this.Justification);
    }
}
