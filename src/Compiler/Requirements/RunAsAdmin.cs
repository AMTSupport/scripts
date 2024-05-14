namespace Compiler.Requirements;

public record RunAsAdminRequirement() : Requirement(false)
{
    public override string GetInsertableLine() => "#Requires -RunAsAdministrator";
}
