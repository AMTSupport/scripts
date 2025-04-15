// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Security.Cryptography;
using System.Text;

namespace Compiler.Requirements;

public enum PSEdition { Desktop, Core }

/// <summary>
/// Represents a PowerShell edition requirement.
/// </summary>
public sealed class PSEditionRequirement : Requirement {
    public PSEdition Edition { get; }

    public PSEditionRequirement(PSEdition edition) : base() {
        this.Edition = edition;
        this.Hash = SHA256.HashData(Encoding.UTF8.GetBytes(this.Edition.ToString()));
    }

    /// Gets the insertable line for the requirement.
    /// <summary>
    /// </summary>
    /// <returns>The insertable line for the requirement.</returns>
    public override string GetInsertableLine(Hashtable data) => $"#Requires -PSEdition {this.Edition}";

    /// <summary>
    /// Determines whether this requirement is compatible with another requirement.
    /// </summary>
    /// <param name="other">The other requirement.</param>
    /// <returns><c>true</c> if this requirement is compatible with the other requirement; otherwise, <c>false</c>.</returns>
    public override bool IsCompatibleWith(Requirement other) {
        if (other is PSEditionRequirement otherEdition) {
            return this.Edition == otherEdition.Edition;
        }

        return true;
    }
}
