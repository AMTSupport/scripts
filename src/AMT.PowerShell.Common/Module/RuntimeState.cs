namespace AMT.PowerShell.Common.Module;

public sealed class RuntimeState(
    string originalPSModulePath,
    string privatePSModulePath,
    string scriptPath,
    string transientScriptPath) {
    public string OriginalPSModulePath { get; } = originalPSModulePath;

    public string PrivatePSModulePath { get; } = privatePSModulePath;

    public string ScriptPath { get; } = scriptPath;

    public string TransientScriptPath { get; } = transientScriptPath;
}
