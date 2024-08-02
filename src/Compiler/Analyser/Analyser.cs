using System.Management.Automation;
using System.Management.Automation.Language;
using Compiler.Module.Compiled;
using NLog;

namespace Compiler.Analyser;

public static class StaticAnalyser
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    /// <summary>
    /// A list of all the built-in functions that are provided in a standard session.
    /// This includes modules that are imported by default.
    /// </summary>
    private static readonly IEnumerable<string> BuiltinsFunctions = GetDefaultSessionFunctions();

    public static void Analyse(CompiledLocalModule module, IEnumerable<Compiled> availableImports)
    {
        Logger.Trace($"Analyzing module {module.ModuleSpec.Name}");

        var undefinedFunctions = FindUndefinedFunctions(module, availableImports);
        if (undefinedFunctions.Count > 0)
        {
            foreach (var undefinedFunction in undefinedFunctions)
            {
                AstHelper.PrintPrettyAstError(undefinedFunction.CommandElements[0].Extent, undefinedFunction, "Undefined function found in module.");
            }

            throw new Exception("Undefined functions found in module.");
        }
    }


    /// <summary>
    /// Get all functions which should always be available in a session.
    /// This will collect the builtin functions of powershell,
    /// as-well as the functions from modules in the compiling hosts C:\Windows\system32\WindowsPowerShell\v1.0\Modules path.
    /// </summary>
    public static IEnumerable<string> GetDefaultSessionFunctions()
    {
        var defaultFunctions = new List<string>();
        var pwsh = PowerShell.Create();
        pwsh.Runspace.SessionStateProxy.LanguageMode = PSLanguageMode.FullLanguage;
        defaultFunctions.AddRange(PowerShell.Create().Runspace.SessionStateProxy.InvokeCommand
            .GetCommands("*", CommandTypes.Function | CommandTypes.Alias | CommandTypes.Cmdlet, true)
            .Select(command => command.Name));

        var modulesPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "Modules");
        var moduleDirectories = Directory.GetDirectories(modulesPath);
        var ps = PowerShell.Create().AddScript(/*ps1*/ $$"""
            $env:PSModulePath = '{{modulesPath}}';
            $env:Path = 'C:\Windows\system32;C:\Windows;C:\Windows\System32\Wbem;C:\Windows\System32\WindowsPowerShell\v1.0\;';
            $PSModuleAutoLoadingPreference = 'All';
            Get-Command * | Select-Object -ExpandProperty Name
        """).Invoke();
        defaultFunctions.AddRange(ps.Select(commandName => ((string)commandName.BaseObject).Replace(".exe", "")));
        return defaultFunctions.Distinct();
    }

    public static List<CommandAst> FindUndefinedFunctions(CompiledLocalModule module, IEnumerable<Compiled> availableImports)
    {
        var calledFunctions = AstHelper.FindCalledFunctions(module.Ast);
        var availableFunctions = new List<string>();
        availableFunctions.AddRange(AstHelper.FindAvailableFunctions(module.Ast, false).Select(definition => {
            return definition.Name.Contains(':') ? definition.Name.Split(':').Last() : definition.Name;
        }));
        availableFunctions.AddRange(availableImports.SelectMany(module => module.GetExportedFunctions()));
        var combinedFunctions = availableFunctions.Concat(BuiltinsFunctions).ToList();
        var unknownCalls = calledFunctions.Where(func => !combinedFunctions.Any(availableFunc => availableFunc == func.GetCommandName()));

        return unknownCalls.ToList();
    }
}
