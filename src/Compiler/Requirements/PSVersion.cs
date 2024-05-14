namespace Compiler.Requirements;

public record PSVersionRequirement(Version Version) : Requirement(false)
{
    public override string GetInsertableLine() => $"#Requires -Version {Version}";
}
