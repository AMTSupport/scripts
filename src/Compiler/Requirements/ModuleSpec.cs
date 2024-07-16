using System.Collections;
using System.Diagnostics.CodeAnalysis;
using System.Security.Cryptography;
using System.Text;
using Compiler.Module;
using NLog;

namespace Compiler.Requirements;

public record PathedModuleSpec(
    string FullPath,
    Guid? Guid = null,
    Version? MinimumVersion = null,
    Version? MaximumVersion = null,
    Version? RequiredVersion = null
) : ModuleSpec(Path.GetFileNameWithoutExtension(FullPath), Guid, MinimumVersion, MaximumVersion, RequiredVersion)
{
    public override byte[] Hash => SHA1.HashData(File.ReadAllBytes(FullPath));

    // TODO - this may not be the best way to do this.
    public override ModuleMatch CompareTo(ModuleSpec other)
    {
        if (other is not PathedModuleSpec && other.Guid == null && other.MinimumVersion == null && other.MaximumVersion == null && other.RequiredVersion == null)
        {
            var otherMaybeFileName = Path.GetFileNameWithoutExtension(other.Name);
            if (Name == otherMaybeFileName) return ModuleMatch.Same;
        }

        return base.CompareTo(other);
    }
}

public record ModuleSpec(
    string Name,
    Guid? Guid = null,
    Version? MinimumVersion = null,
    Version? MaximumVersion = null,
    Version? RequiredVersion = null
) : Requirement(true), IEquatable<ModuleSpec>
{
    private readonly static Logger Logger = LogManager.GetCurrentClassLogger();

    public override uint Weight => 70;

    public override byte[] Hash => SHA1.HashData(Encoding.UTF8.GetBytes(string.Concat(Name, Guid, MinimumVersion, MaximumVersion, RequiredVersion)));

    // TODO - Maybe use IsCompatibleWith to do some other check stuff
    public ModuleSpec MergeSpecs(ModuleSpec[] merge)
    {
        var guid = Guid;
        var minVersion = MinimumVersion;
        var maxVersion = MaximumVersion;
        var reqVersion = RequiredVersion;

        foreach (var match in merge)
        {
            if (match.Guid != null && guid == null)
            {
                Logger.Debug($"Merging {Name} with {match.Name} - {Guid} -> {match.Guid}");
                guid = match.Guid;
            }

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

            if (match.RequiredVersion != null && reqVersion == null)
            {
                Logger.Debug($"Merging {Name} with {match.Name} - {RequiredVersion} -> {match.RequiredVersion}");
                reqVersion = match.RequiredVersion;
            }
        }

        return new ModuleSpec(Name, guid, minVersion, maxVersion, reqVersion);
    }

    public override string GetInsertableLine(Hashtable data)
    {
        var nameSuffix = data.ContainsKey("NameSuffix") ? $"-{data["NameSuffix"]}" : string.Empty;
        var moduleName = $"{Path.GetFileNameWithoutExtension(Name)}{nameSuffix}";

        if (Guid == null && RequiredVersion == null && MinimumVersion == null && MaximumVersion == null)
        {
            return $"Using module '{moduleName}'";
        }

        var sb = new StringBuilder("Using module @{");
        sb.Append($"ModuleName = '{moduleName}';");
        if (Guid != null) sb.Append($"GUID = {Guid};");

        switch (RequiredVersion, MinimumVersion, MaximumVersion)
        {
            case (null, null, null): break;
            case (null, var min, var max) when min != null && max != null: sb.Append($"ModuleVersion = '{min}';MaximumVersion = '{max}';"); break;
            case (null, var min, _) when min != null: sb.Append($"ModuleVersion = '{min}';"); break;
            case (null, _, var max) when max != null: sb.Append($"MaximumVersion = '{max}';"); break;
            case (var req, _, _): sb.Append($"RequiredVersion = '{req}';"); break;
        }

        sb.Append('}');
        return sb.ToString();
    }

    public virtual ModuleMatch CompareTo(ModuleSpec other)
    {
        if (Name != other.Name) return ModuleMatch.None;
        if (Guid != null && other.Guid != null && Guid != other.Guid) return ModuleMatch.None;

        var isStricter = false;
        var isLooser = false;
        switch ((MinimumVersion, other.MinimumVersion))
        {
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

        switch ((MaximumVersion, other.MaximumVersion))
        {
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

        switch ((RequiredVersion, other.RequiredVersion))
        {
            case (null, null):
                break;
            case (null, var b) when (MinimumVersion != null && b < MinimumVersion) || (MaximumVersion != null && b > MaximumVersion):
                return ModuleMatch.Incompatible;
            case (var a, null) when (other.MinimumVersion != null && a < other.MinimumVersion) || (other.MaximumVersion != null && a > other.MaximumVersion):
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
        if (isStricter && isLooser) return ModuleMatch.MergeRequired;
        if (isStricter) return ModuleMatch.Stricter;
        if (isLooser) return ModuleMatch.Looser;

        return ModuleMatch.Same;
    }

    [ExcludeFromCodeCoverage(Justification = "Just a bool flag.")]
    public override bool IsCompatibleWith(Requirement other) => true;

    public override int GetHashCode() => HashCode.Combine(Name, Guid, MinimumVersion, MaximumVersion, RequiredVersion);
}

