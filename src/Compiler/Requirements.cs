using System;
using System.Collections;

public abstract class Requirement;

public class VersionRequirement : Requirement
{
    public Version Version { get; }

    public VersionRequirement(Version version)
    {
        Version = version;
    }
}

public class ModuleRequirement : Requirement
{
    public Hashtable Modules { get; }

    public ModuleRequirement()
    {
        Modules = new Hashtable();
    }

    public void AddModule(string name) {
        Modules.Add(name, new Hashtable());
    }

    public void AddModule(string name, Hashtable properties) {
        Modules.Add(name, properties);
    }
}
