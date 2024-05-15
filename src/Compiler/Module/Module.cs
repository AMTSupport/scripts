using Compiler.Requirements;

namespace Compiler.Module;

public abstract partial class Module(ModuleSpec moduleSpec)
{
    public string Name => ModuleSpec.Name;
    public Version Version => ModuleSpec.RequiredVersion ?? new Version(0, 0, 0, 0);
    public ModuleSpec ModuleSpec { get; } = moduleSpec;
    public Requirements.Requirements Requirements { get; } = new();

    public abstract ModuleMatch GetModuleMatchFor(ModuleSpec requirement);

    public abstract string GetContent(int indent = 0);

    public string GetInsertableContent(int indent = 0)
    {
        var indentStr = new string(' ', indent);
        return $$"""
        {{indentStr}}'{{Name}}' = @{
        {{indentStr}}    Type = '{{ModuleSpec.Type}}';
        {{indentStr}}    Content = {{GetContent(indent + 4)}};
        {{indentStr}}};
        """;
    }
}

public enum ModuleMatch
{
    // This module is an exact match for the requirement
    Exact,

    // This module is a higher version than the requirement
    Above,

    // This module has a version that makes it incompatible with the requirement
    Incompatible,

    // This module does not match the requirement
    None
}
