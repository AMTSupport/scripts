using System.Text;

namespace Compiler.Requirements;

public record PSVersionRequirement(Version Version) : Requirement(false)
{
    public override string GetInsertableLine()
    {
        var sb = new StringBuilder();
        sb.Append("#Requires -Version ");
        sb.Append(Version.Major);

        var hasBuild = Version.Build > 0;
        if (Version.Minor > 0 || hasBuild)
        {
            sb.Append($".{Version.Minor}");

            if (hasBuild)
            {
                sb.Append($".{Version.Build}");
            }
        }

        return sb.ToString();
    }

    // TODO - Check modules for version compatibility
    public override bool IsCompatibleWith(Requirement other) => (this, other) switch
    {
        (var current, PSVersionRequirement otherVersion) when current.Version.Major == otherVersion.Version.Major => true,
        (var current, PSVersionRequirement otherVersion) when (otherVersion.Version.Major <= 4 && current.Version.Major > 4) || (otherVersion.Version.Major > 4 && current.Version.Major <= 4) => false,
        _ => true
    };
}
