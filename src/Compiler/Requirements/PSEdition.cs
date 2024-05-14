namespace Compiler.Requirements;

public record PSEditionRequirement(PSEdition Edition) : Requirement(false)
{
    public override string GetInsertableLine() => $"#Requires -PSEdition {Edition}";
}
