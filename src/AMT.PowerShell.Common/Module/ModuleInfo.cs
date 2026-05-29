namespace AMT.PowerShell.Common.Module;

public sealed class ModuleInfo(string name, string version, string description) {
    public string Name { get; } = name;

    public string Version { get; } = version;

    public string Description { get; } = description;
}
