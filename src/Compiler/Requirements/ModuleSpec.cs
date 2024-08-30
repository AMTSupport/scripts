// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Compiler.Module;
using LanguageExt;
using NLog;

namespace Compiler.Requirements;

public sealed class PathedModuleSpec : ModuleSpec {
    private Option<byte[]> LazyHash = None;

    public readonly string FullPath;

    public override byte[] Hash {
        get {
            if (this.LazyHash.IsSome(out var hash)) return hash;
            var newHash = SHA256.HashData(File.ReadAllBytes(this.FullPath));
            this.LazyHash = Some(newHash);
            return newHash;
        }
        protected set => this.LazyHash = Some(value);
    }

    /// <summary>
    /// Creates a new PathedModuleSpec from a full path.
    /// </summary>
    /// <param name="fullPath"></param>
    /// <param name="id"></param>
    /// <param name="minimumVersion"></param>
    /// <param name="maximumVersion"></param>
    /// <param name="requiredVersion"></param>
    /// <exception cref="FileNotFoundException">
    /// Thrown when the file cannot be found, or read.
    /// </exception>
    public PathedModuleSpec(
        string fullPath,
        Guid? id = null,
        Version? minimumVersion = null,
        Version? maximumVersion = null,
        Version? requiredVersion = null
    ) : base(Path.GetFileNameWithoutExtension(fullPath), id, minimumVersion, maximumVersion, requiredVersion) {
        this.FullPath = fullPath;
        this.Weight = 73;
    }

    // TODO - this may not be the best way to do this.
    public override ModuleMatch CompareTo(ModuleSpec other) {
        if (other is not PathedModuleSpec && other.Id == null && other.MinimumVersion == null && other.MaximumVersion == null && other.RequiredVersion == null) {
            var otherMaybeFileName = Path.GetFileNameWithoutExtension(other.Name);
            if (this.Name == otherMaybeFileName) return ModuleMatch.PreferOurs;
        }

        return base.CompareTo(other);
    }
}

public class ModuleSpec : Requirement {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    public string Name { get; }
    public Guid? Id { get; }
    public Version? MinimumVersion { get; }
    public Version? MaximumVersion { get; }
    public Version? RequiredVersion { get; }

    public ModuleSpec(
        string name,
        Guid? id = null,
        Version? minimumVersion = null,
        Version? maximumVersion = null,
        Version? requiredVersion = null
    ) : base() {
        this.SupportsMultiple = true;
        this.Weight = 70;

        this.Name = name;
        this.Id = id;
        this.MinimumVersion = minimumVersion;
        this.MaximumVersion = maximumVersion;
        this.RequiredVersion = requiredVersion;

        this.Hash = SHA256.HashData(Encoding.UTF8.GetBytes(string.Concat(this.Name, this.Id, this.MinimumVersion, this.MaximumVersion, this.RequiredVersion)));
    }

    // TODO - Maybe use IsCompatibleWith to do some other check stuff
    public ModuleSpec MergeSpecs(ModuleSpec[] merge) {
        var guid = this.Id;
        var minVersion = this.MinimumVersion;
        var maxVersion = this.MaximumVersion;
        var reqVersion = this.RequiredVersion;

        foreach (var match in merge) {
            if (match.Id != null && guid == null) {
                Logger.Debug($"Merging {this.Name} with {match.Name} - {guid?.ToString() ?? "null"} -> {match.Id}");
                guid = match.Id;
            }

            if (match.MinimumVersion != null && (minVersion == null || match.MinimumVersion > minVersion)) {
                Logger.Debug($"Merging {this.Name} with {match.Name} - {minVersion?.ToString() ?? "null"} -> {match.MinimumVersion}");
                minVersion = match.MinimumVersion;
            }

            if (match.MaximumVersion != null && (maxVersion == null || match.MaximumVersion < maxVersion)) {
                Logger.Debug($"Merging {this.Name} with {match.Name} - {maxVersion?.ToString() ?? "null"} -> {match.MaximumVersion}");
                maxVersion = match.MaximumVersion;
            }

            if (match.RequiredVersion != null && reqVersion == null) {
                Logger.Debug($"Merging {this.Name} with {match.Name} - {this.RequiredVersion?.ToString() ?? "null"} -> {match.RequiredVersion}");
                reqVersion = match.RequiredVersion;
            }
        }

        return new ModuleSpec(this.Name, guid, minVersion, maxVersion, reqVersion);
    }

    public override string GetInsertableLine(Hashtable data) {
        var nameSuffix = data.ContainsKey("NameSuffix") ? $"-{data["NameSuffix"]}" : string.Empty;
        var moduleName = $"{this.Name}{nameSuffix}";

        if (this.Id == null && this.RequiredVersion == null && this.MinimumVersion == null && this.MaximumVersion == null) {
            return $"Using module '{moduleName}'";
        }

        var sb = new StringBuilder("Using module @{");
        sb.Append(CultureInfo.InvariantCulture, $"ModuleName = '{moduleName}';");
        if (this.Id != null) sb.Append(CultureInfo.InvariantCulture, $"GUID = {this.Id};");

        switch (this.RequiredVersion, this.MinimumVersion, this.MaximumVersion) {
            case (null, null, null): break;
            case (null, var min, var max) when min != null && max != null: sb.Append(CultureInfo.InvariantCulture, $"ModuleVersion = '{min}';MaximumVersion = '{max}';"); break;
            case (null, var min, _) when min != null: sb.Append(CultureInfo.InvariantCulture, $"ModuleVersion = '{min}';"); break;
            case (null, _, var max) when max != null: sb.Append(CultureInfo.InvariantCulture, $"MaximumVersion = '{max}';"); break;
            case (var req, _, _): sb.Append(CultureInfo.InvariantCulture, $"RequiredVersion = '{req}';"); break;
        }

        sb.Append('}');
        return sb.ToString();
    }

    public virtual ModuleMatch CompareTo(ModuleSpec other) {
        if (ReferenceEquals(this, other)) return ModuleMatch.Same;
        if (this.Name != other.Name) return ModuleMatch.None;
        if (this.Id != null && other.Id != null && this.Id != other.Id) return ModuleMatch.None;

        var isStricter = false;
        var isLooser = false;
        switch ((this.MinimumVersion, other.MinimumVersion)) {
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

        switch ((this.MaximumVersion, other.MaximumVersion)) {
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

        if (this.MinimumVersion != null && other.MaximumVersion != null && this.MinimumVersion > other.MaximumVersion) return ModuleMatch.Incompatible;
        if (other.MinimumVersion != null && this.MaximumVersion != null && other.MinimumVersion > this.MaximumVersion) return ModuleMatch.Incompatible;

        switch ((this.RequiredVersion, other.RequiredVersion)) {
            case (null, null):
                break;
            case (null, var b) when (this.MinimumVersion != null && b < this.MinimumVersion) || (this.MaximumVersion != null && b > this.MaximumVersion):
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

    public override int GetHashCode() => HashCode.Combine(this.Name, this.Id, this.MinimumVersion, this.MaximumVersion, this.RequiredVersion);

    public override int CompareTo(Requirement? other) {
        if (other is not ModuleSpec) return 0;
        return this.CompareTo((ModuleSpec)other).CompareTo(ModuleMatch.Same);
    }

    public override bool Equals(object? obj) {
        if (obj is null) return false;
        if (obj is not ModuleSpec other) return false;
        if (ReferenceEquals(this, other)) return true;
        return this.Name == other.Name && this.Id == other.Id && this.MinimumVersion == other.MinimumVersion && this.MaximumVersion == other.MaximumVersion && this.RequiredVersion == other.RequiredVersion;
    }

    public override string ToString() => JsonSerializer.Serialize(this, SerializerOptions);
}

