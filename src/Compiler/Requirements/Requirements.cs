using System.Collections;
using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Compiler.Requirements;

public sealed class RequirementGroup
{
    public Dictionary<Type, HashSet<Requirement>> StoredRequirements { get; init; }

    public RequirementGroup()
    {
        StoredRequirements ??= [];
    }

    public bool AddRequirement<T>(T value) where T : Requirement
    {
        var typeName = typeof(T);
        if (!StoredRequirements.TryGetValue(typeName, out HashSet<Requirement>? requirementList))
        {
            StoredRequirements.Add(typeName, [value]);
            return true;
        }
        else
        {
            return requirementList.Add(value);
        }
    }

    public ImmutableList<T> GetRequirements<T>() where T : Requirement
    {
        var typeName = typeof(T);
        if (StoredRequirements.TryGetValue(typeName, out HashSet<Requirement>? value))
        {
            return value.Cast<T>().ToImmutableList();
        }

        return [];
    }

    public bool RemoveRequirement<T>(T value) where T : Requirement
    {
        var typeName = typeof(T);
        if (StoredRequirements.TryGetValue(typeName, out HashSet<Requirement>? collection))
        {
            return collection.Remove(value);
        }

        return false;
    }

    public ImmutableList<Requirement> GetRequirements()
    {
        var rawRequirements = StoredRequirements.Values;
        if (rawRequirements.Count == 0) return [];

        var flattenedList = rawRequirements.ToList().SelectMany(x => x);
        // bubble sort the requirements by their weight
        return [.. flattenedList.OrderBy(x => x, new RequirementWeightSorter())];
    }
}

/// <summary>
///  Represents a requirement, which is a condition that must be met in order to run the script.
/// </summary>
/// <param name="SupportsMultiple">
/// True if the requirement supports multiple instances, false otherwise.
/// </param>
public abstract class Requirement : IComparable<Requirement>
{
    protected static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    /// <summary>
    /// Indicates if the requirement supports multiple instances.
    /// </summary>
    [JsonIgnore]
    public bool SupportsMultiple { get; protected set; }

    /// <summary>
    /// Gets the weight of the requirement.
    /// This weight is used for the order when inserting the requirements.
    /// </summary>
    [JsonIgnore]
    public uint Weight { get; protected set; } = 50;

    /// <summary>
    /// Gets the hash of the requirement.
    ///
    /// This is implemented by the derived class.
    /// </summary>
    [JsonIgnore]
    public byte[] Hash { get; protected set; } = [];

    /// <summary>
    /// Used only for serialization purposes.
    /// </summary>
    [JsonInclude]
    internal string HashString => Convert.ToHexString(Hash);

    /// <summary>
    /// Checks if the requirement is compatible with another requirement.
    /// </summary>
    public abstract bool IsCompatibleWith(Requirement other);

    /// <summary>
    /// Gets the insertable line for the requirement.
    /// This is the code which will be inserted into the script.
    /// </summary>
    public abstract string GetInsertableLine(Hashtable data);

    public virtual int CompareTo(Requirement? other) => 0;

    public override string ToString() => JsonSerializer.Serialize(this, SerializerOptions);
}

/// <summary>
/// Sorts requirements by their weight.
/// </summary>
public sealed class RequirementWeightSorter : IComparer<Requirement>
{
    public int Compare(Requirement? x, Requirement? y)
    {
        if (ReferenceEquals(x, y)) return 0;
        if (x == null) return y == null ? 0 : -1;
        if (y == null) return x == null ? 0 : 1;

        var weight = x.Weight.CompareTo(y?.Weight);
        if (weight != 0) return weight;
        return x.CompareTo(y);
    }
}
