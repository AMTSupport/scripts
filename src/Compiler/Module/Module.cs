using Compiler.Requirements;

namespace Compiler.Module;

public abstract partial class Module(ModuleSpec moduleSpec)
{
    public string Name => ModuleSpec.Name;
    public Version Version => ModuleSpec.RequiredVersion ?? new Version(0, 0, 0, 0);
    public ModuleSpec ModuleSpec { get; } = moduleSpec;
    public RequirementGroup Requirements { get; } = new();

    public abstract ModuleMatch GetModuleMatchFor(ModuleSpec requirement);

    public abstract string GetContent(int indent = 0);

    public string GetInsertableContent(int indent = 0)
    {
        var indentStr = new string(' ', indent);
        return $$"""
        {{indentStr}}'{{Name}}' = @{
        {{indentStr}}    Type = '{{GetType().Name}}';
        {{indentStr}}    Content = {{GetContent(indent + 4)}};
        {{indentStr}}};
        """;
    }
}

public enum ModuleMatch
{
    /// <summary>
    /// This module matches the requirements and doesn't have any additional restrictions.
    /// </summary>
    Same,

    /// <summary>
    /// This module fulfills the requirements, but has a stricter scope.
    /// </summary>
    Stricter,

    /// <summary>
    /// This module fulfills the requirements, but has a looser scope.
    /// </summary>
    Looser,

    /// <summary>
    /// This module has incompatible restrictions.
    /// </summary>
    Incompatible,

    /// <summary>
    /// This module does not match the requirements.
    /// </summary>
    None
}
