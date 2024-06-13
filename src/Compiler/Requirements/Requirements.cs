using System.Collections;
using CommandLine;
using NLog;

namespace Compiler.Requirements;

public class RequirementGroup
{
    private readonly static Logger Logger = LogManager.GetCurrentClassLogger();
    public Hashtable StoredRequirements { get; }

    public RequirementGroup()
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
            return StoredRequirements[typeof(T)].Cast<List<Requirement>>().FindAll(requirement => requirement is T).Cast<T>().ToList();
        }

        return [];
    }

    public List<Requirement> GetRequirements()
    {
        return StoredRequirements.Values.Cast<List<Requirement>>().SelectMany(requirements => requirements).ToList();
    }

    // FIXME - Not very efficient
    public bool VerifyRequirements()
    {
        foreach (var requirement in GetRequirements<Requirement>())
        {
            foreach (var other in GetRequirements<Requirement>())
            {
                if (!requirement.IsCompatibleWith(other))
                {
                    Logger.Error($"Requirement {requirement} is incompatible with {other}");
                    return false;
                }

                Logger.Debug($"Requirement {requirement} is compatible with {other}");
            }
        }

        return true;
    }
}

public abstract record Requirement(bool SupportsMultiple)
{
    public abstract bool IsCompatibleWith(Requirement other);

    public abstract string GetInsertableLine();
}

public enum ModuleType
{
    Downloadable,
    Local
}

public enum PSEdition { Desktop, Core }
