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
        flattenedList.Sort((x, y) => x.GetType().Name.CompareTo(y.GetType().Name));
        return [.. flattenedList];
    }

    // FIXME - Not very efficient
    public bool VerifyRequirements()
    {
        var hadError = false;
        var requirements = GetRequirements();
        requirements.SelectMany(x => requirements.Where(y => !x.IsCompatibleWith(y))).ToList().ForEach(x =>
        {
            Logger.Error($"Requirement {x} is incompatible with another requirement");
            hadError = true;
        });

        return !hadError;
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
