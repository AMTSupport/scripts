using System.Text;

namespace Compiler.Requirements;

public record ModuleSpec(
    string Name,
    Guid? Guid = null,
    Version? MinimumVersion = null,
    Version? MaximumVersion = null,
    Version? RequiredVersion = null,
    ModuleType Type = ModuleType.Downloadable
) : Requirement(true)
{
    public override string GetInsertableLine()
    {
        var sb = new StringBuilder("#Requires -Modules @{");

        sb.Append($"ModuleName = '{Name}';");
        if (Guid != null) sb.Append($"GUID = {Guid};");
        sb.Append($"ModuleVersion = '{(MinimumVersion != null ? MinimumVersion.ToString() : "0.0.0.0")}';");
        if (MaximumVersion != null) sb.Append($"MaximumVersion = '{MaximumVersion}';");
        if (RequiredVersion != null) sb.Append($"RequiredVersion = '{RequiredVersion}';");
        sb.Append('}');

        return sb.ToString();
    }
}
