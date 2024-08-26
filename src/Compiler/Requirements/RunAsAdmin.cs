// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Diagnostics.CodeAnalysis;
using System.Security.Cryptography;
using System.Text;

namespace Compiler.Requirements;

public sealed class RunAsAdminRequirement : Requirement {
    private const string STRING = "#Requires -RunAsAdministrator";

    public RunAsAdminRequirement() : base() {
        this.SupportsMultiple = false;
        this.Hash = SHA256.HashData(Encoding.UTF8.GetBytes(STRING));
    }

    [ExcludeFromCodeCoverage(Justification = "It's just a string.")]
    public override string GetInsertableLine(Hashtable data) => STRING;

    [ExcludeFromCodeCoverage(Justification = "Just a sick as fuck bool man!")]
    public override bool IsCompatibleWith(Requirement other) => true;
}
