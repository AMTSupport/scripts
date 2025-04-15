// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace Compiler.Requirements;

public sealed class PSVersionRequirement : Requirement {
    public Version Version { get; }

    public PSVersionRequirement(Version version) : base() {
        this.SupportsMultiple = false;

        this.Version = version;
        this.Hash = SHA256.HashData(Encoding.UTF8.GetBytes(this.Version.ToString()));
    }

    public override string GetInsertableLine(Hashtable data) {
        var sb = new StringBuilder();
        sb.Append("#Requires -Version ");
        sb.Append(this.Version.Major);

        var hasBuild = this.Version.Build > 0;
        if (this.Version.Minor > 0 || hasBuild) {
            sb.Append(CultureInfo.InvariantCulture, $".{this.Version.Minor}");

            if (hasBuild) {
                sb.Append(CultureInfo.InvariantCulture, $".{this.Version.Build}");
            }
        }

        return sb.ToString();
    }

    public override bool IsCompatibleWith([NotNull] Requirement other) => (this, other) switch {
        // TODO - Check modules for version compatibility
        // Short circuit for non-version requirements
        (_, var otherRequirement) when otherRequirement is not PSVersionRequirement => true,

        // Short circuit for the same version
        (var current, PSVersionRequirement otherVersion) when current.Version.Major == otherVersion.Version.Major => true,

        // General rule of thumb is anything less than 4 is not compatible with anything greater than 4
        (var current, PSVersionRequirement otherVersion) when (otherVersion.Version.Major <= 4 && current.Version.Major > 4) || (otherVersion.Version.Major > 4 && current.Version.Major <= 4) => false,

        // If the other version is greater than the current version, it's compatible
        (var current, PSVersionRequirement otherVersion) when current.Version.Major < otherVersion.Version.Major => true,

        // If the other version is less than the current version, it's not compatible
        (var current, PSVersionRequirement otherVersion) when current.Version.Major > otherVersion.Version.Major => false,

        // If it passed all this its probably compatible
        (_, var otherRequirement) when otherRequirement is PSVersionRequirement => true,

        // This should never happen, but compiler will complain if it's not here
        _ => true
    };
}
