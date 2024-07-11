using System.Collections;
using System.Diagnostics.CodeAnalysis;
using System.Security.Cryptography;
using System.Text;

namespace Compiler.Requirements;

public record RunAsAdminRequirement() : Requirement(false)
{
    const string STRING = "#Requires -RunAsAdministrator";

    public override byte[] Hash => SHA1.HashData(Encoding.UTF8.GetBytes(STRING));

    [ExcludeFromCodeCoverage(Justification = "It's just a string.")]
    public override string GetInsertableLine(Hashtable _) => STRING;

    [ExcludeFromCodeCoverage(Justification = "Just a sick as fuck bool man!")]
    public override bool IsCompatibleWith(Requirement other) => true;
}
