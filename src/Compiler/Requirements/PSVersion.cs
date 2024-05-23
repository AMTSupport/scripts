namespace Compiler.Requirements;

public record PSVersionRequirement(Version Version) : Requirement(false)
{
    public override string GetInsertableLine() => $"#Requires -Version {Version}";

    // TODO - Check modules for version compatibility
    public override bool IsCompatibleWith(Requirement other) => (this, other) switch
    {
        (var current, PSVersionRequirement otherVersion) when current.Version.Major == otherVersion.Version.Major => true,
        (var current, PSVersionRequirement otherVersion) when (otherVersion.Version.Major <= 4 && current.Version.Major > 4) || (otherVersion.Version.Major > 4 && current.Version.Major <= 4) => false,
        _ => true
    };
}
