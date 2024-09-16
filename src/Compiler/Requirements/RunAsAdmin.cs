// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Security.Cryptography;
using System.Text;

namespace Compiler.Requirements;

public sealed class RunAsAdminRequirement : Requirement {
    private const string STRING = "#Requires -RunAsAdministrator";

    public RunAsAdminRequirement() : base() {
        this.SupportsMultiple = false;
        this.Hash = SHA256.HashData(Encoding.UTF8.GetBytes(STRING));
    }

    public override string GetInsertableLine(Hashtable data) => STRING;

    public override bool IsCompatibleWith(Requirement other) => true;
}
