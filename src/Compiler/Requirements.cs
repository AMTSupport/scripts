using System.Collections;
using CommandLine;

namespace Compiler
{
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

        // TODO
        public bool VerifyRequirements()
        {
            return true;
        }
    }

    public abstract class Requirement;

    public class VersionRequirement(Version version) : Requirement
    {
        public Version Version { get; } = version;
    }

    public class ModuleSpec(
        string name,
        Guid? guid = null,
        Version? mimimumVersion = null,
        Version? maximumVersion = null,
        Version? requiredVersion = null
        ) : Requirement
    {
        public string Name { get; } = name;
        public Guid? Guid { get; } = guid;
        public Version? MimimumVersion { get; } = mimimumVersion;
        public Version? MaximumVersion { get; } = maximumVersion;
        public Version? RequiredVersion { get; } = requiredVersion;
        public ModuleType Type { get; } = ModuleType.Downloadable;

        public enum ModuleType
        {
            Downloadable,
            Local
        }
    }
}
