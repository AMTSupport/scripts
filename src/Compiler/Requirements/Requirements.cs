using System.Collections;
using System.Text;
using CommandLine;

namespace Compiler.Requirements;

public class Requirements
{
    public Hashtable StoredRequirements { get; }

    public Requirements()
    {
        StoredRequirements = [];
    }

    public void AddRequirement(Requirement value)
    {
        if (!StoredRequirements.ContainsKey(value.GetType()))
        {
            StoredRequirements.Add(value.GetType(), new List<Requirement> { value });
        }
        else
        {
            StoredRequirements[value.GetType()].Cast<List<Requirement>>().Add(value);
        }
    }

    public List<T> GetRequirements<T>()
    {
        if (StoredRequirements.ContainsKey(typeof(T)))
        {
            return StoredRequirements[typeof(T)].Cast<List<Requirement>>().FindAll(requirement => requirement.CanCast<T>()).Cast<T>().ToList();
        }

        return [];
    }

    public List<Requirement> GetRequirements()
    {
        return StoredRequirements.Values.Cast<List<Requirement>>().SelectMany(requirements => requirements).ToList();
    }

    // TODO
    public bool VerifyRequirements()
    {
        return true;
    }
}

public abstract record Requirement(bool SupportsMultiple)
{
    public abstract string GetInsertableLine();
}

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

public enum ModuleType
{
    Downloadable,
    Local
}

public enum PSEdition { Desktop, Core }
