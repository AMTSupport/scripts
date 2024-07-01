using System.Collections.Immutable;
using NLog;

namespace Compiler.Requirements;

public class RequirementGroup
{
    private readonly static Logger Logger = LogManager.GetCurrentClassLogger();
    public Dictionary<Type, List<Requirement>> StoredRequirements { get; }

    public RequirementGroup()
    {
        StoredRequirements = [];
    }

    public void AddRequirement<T>(T value) where T : Requirement
    {
        var typeName = typeof(T);
        if (!StoredRequirements.TryGetValue(typeName, out List<Requirement>? requirementList))
        {
            StoredRequirements.Add(typeName, [value]);
        }
        else
        {
            requirementList.Add(value);
        }
    }

    public ImmutableHashSet<T> GetRequirements<T>() where T : Requirement
    {
        var typeName = typeof(T);
        if (StoredRequirements.TryGetValue(typeName, out List<Requirement>? value))
        {
            return value.Cast<T>().ToImmutableHashSet();
        }

        return [];
    }

    public bool RemoveRequirement<T>(T value) where T : Requirement
    {
        var typeName = typeof(T);
        if (StoredRequirements.TryGetValue(typeName, out List<Requirement>? collection))
        {
            return collection.Remove(value);
        }

        return false;
    }

    public bool ReplaceRequirement<T>(T oldValue, T newValue) where T : Requirement
    {
        var typeName = typeof(T);
        if (StoredRequirements.TryGetValue(typeName, out List<Requirement>? value))
        {
            var index = value.ToList().IndexOf(oldValue);
            if (index != -1)
            {
                value[index] = newValue;
                return true;
            }
        }

        return false;
    }

    public ImmutableHashSet<Requirement> GetRequirements()
    {
        var rawRequirements = StoredRequirements.Values;
        if (rawRequirements.Count == 0)
        {
            Logger.Debug("No requirements found");
            return [];
        }

        var flattenedList = StoredRequirements.Values.ToList().SelectMany(x => x).ToList();
        flattenedList.Sort(new RequirementWeightSorter());
        return [.. flattenedList];
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
    public virtual uint Weight => 50;

    public abstract byte[] Hash { get; }

    public abstract bool IsCompatibleWith(Requirement other);

    public abstract string GetInsertableLine();
}

public class RequirementWeightSorter : IComparer<Requirement>
{
    public int Compare(Requirement? x, Requirement? y)
    {
        if (x == null)
        {
            return y == null ? 0 : -1;
        }

        return x.Weight.CompareTo(y?.Weight);
    }
}
