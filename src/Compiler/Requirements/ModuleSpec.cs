using System.Text;
using Compiler.Module;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using NLog;

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
    private readonly static Logger Logger = LogManager.GetCurrentClassLogger();

    public ModuleSpec MergeSpecs(ModuleSpec[] merge)
    {
        var minVersion = MinimumVersion;
        var maxVersion = MaximumVersion;
        var reqVersion = RequiredVersion;

        foreach (var match in merge)
        {
            if (match.MinimumVersion != null && (minVersion == null || match.MinimumVersion > minVersion))
            {
                Logger.Debug($"Merging {Name} with {match.Name} - {minVersion} -> {match.MinimumVersion}");
                minVersion = match.MinimumVersion;
            }

            if (match.MaximumVersion != null && (maxVersion == null || match.MaximumVersion < maxVersion))
            {
                Logger.Debug($"Merging {Name} with {match.Name} - {maxVersion} -> {match.MaximumVersion}");
                maxVersion = match.MaximumVersion;
            }

            if (match.RequiredVersion != null && (reqVersion == null || match.RequiredVersion > reqVersion))
            {
                throw new Exception("Cannot merge requirements with different required versions");
            }
        }

        return new ModuleSpec(Name, Guid, minVersion, maxVersion, reqVersion, Type);
    }

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

    public ModuleMatch CompareTo(ModuleSpec other)
    {
        if (Name != other.Name) return ModuleMatch.None;
        if (Guid != null && other.Guid != null && Guid != other.Guid) return ModuleMatch.None;

        var isStricter = false;
        var isLooser = false;
        switch ((MinimumVersion, other.MinimumVersion)) {
            case (null, null):
                break;
            case (null, _):
                isLooser = true;
                break;
            case (_, null):
                isStricter = true;
                break;
            case (var a, var b) when a > b:
                isStricter = true;
                break;
            case (var a, var b) when a < b:
                isLooser = true;
                break;
        }

        switch ((MaximumVersion, other.MaximumVersion)) {
            case (null, null):
                break;
            case (null, _):
                isLooser = true;
                break;
            case (_, null):
                isStricter = true;
                break;
            case (var a, var b) when a < b:
                isStricter = true;
                break;
            case (var a, var b) when a > b:
                isLooser = true;
                break;
        }

        if (MinimumVersion != null && other.MaximumVersion != null && MinimumVersion > other.MaximumVersion) return ModuleMatch.Incompatible;
        if (other.MinimumVersion != null && MaximumVersion != null && other.MinimumVersion > MaximumVersion) return ModuleMatch.Incompatible;

        switch ((RequiredVersion, other.RequiredVersion)) {
            case (null, null):
                break;
            case (null, var b) when b < MinimumVersion || b > MaximumVersion:
                return ModuleMatch.Incompatible;
            case (var a, null) when a < other.MinimumVersion || a > other.MaximumVersion:
                return ModuleMatch.Incompatible;
            case (_, null):
                isStricter = true;
                isLooser = false; // A RequiredVersion overrides version ranges
                break;
            case (null, _):
                isStricter = false; // A RequiredVersion overrides version ranges
                isLooser = true;
                break;
            case (var a, var b) when a != b:
                return ModuleMatch.Incompatible;
        }

        // We can't really determine if its higher or lower so we just call it the same.
        if (isStricter && isLooser) return ModuleMatch.Same;
        if (isStricter) return ModuleMatch.Stricter;
        if (isLooser) return ModuleMatch.Looser;

        return ModuleMatch.Same;
    }
}

