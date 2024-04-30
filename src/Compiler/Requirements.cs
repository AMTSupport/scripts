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

        public void AddRequirement(object value)
        {
            if (!StoredRequirements.ContainsKey(value.GetType()))
            {
                StoredRequirements.Add(value.GetType(), new List<object> { value });
            }
            else
            {
                StoredRequirements[value.GetType()].Cast<List<object>>().Add(value);
            }
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

    public class ModuleRequirement(
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
