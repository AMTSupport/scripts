using System.Collections;
using System.Collections.Immutable;
using System.Configuration;
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
        if (rawRequirements.Count == 0) return [];

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

/// <summary>
///  Represents a requirement, which is a condition that must be met in order to run the script.
/// </summary>
/// <param name="SupportsMultiple">
/// True if the requirement supports multiple instances, false otherwise.
/// </param>
public abstract record Requirement(bool SupportsMultiple)
{
    /// <summary>
    /// Gets the weight of the requirement.
    /// This weight is used for the order when inserting the requirements.
    /// </summary>
    public virtual uint Weight => 50;

    /// <summary>
    /// Gets the hash of the requirement.
    ///
    /// This is implemented by the derived class.
    /// </summary>
    public abstract byte[] Hash { get; }

    /// <summary>
    /// Checks if the requirement is compatible with another requirement.
    /// </summary>
    public abstract bool IsCompatibleWith(Requirement other);

    /// <summary>
    /// Gets the insertable line for the requirement.
    /// This is the code which will be inserted into the script.
    /// </summary>
    public abstract string GetInsertableLine(Hashtable data);

    bool IEquatable<Requirement>.Equals(Requirement? obj)
    {
        if (obj == null) return false;
        return obj.Hash.SequenceEqual(Hash);

    }
}

/// <summary>
/// Sorts requirements by their weight.
/// </summary>
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
