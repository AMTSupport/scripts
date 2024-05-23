using System.Diagnostics.CodeAnalysis;

namespace Compiler.Requirements;

public record RunAsAdminRequirement() : Requirement(false)
{
    const string STRING = "#Requires -RunAsAdministrator";

    [ExcludeFromCodeCoverage(Justification = "It's just a string.")]
    public override string GetInsertableLine() => STRING;

    [ExcludeFromCodeCoverage(Justification = "Just a sick as fuck bool man!")]
    public override bool IsCompatibleWith(Requirement other) => true;
}
