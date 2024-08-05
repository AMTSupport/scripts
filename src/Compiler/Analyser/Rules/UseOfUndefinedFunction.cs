using System.Management.Automation;
using System.Management.Automation.Language;
using Compiler.Module.Compiled;

namespace Compiler.Analyser.Rules;

public class UseOfUndefinedFunction : Rule
{
    /// <summary>
    /// A list of all the built-in functions that are provided in a standard session.
    /// This includes modules that are imported by default.
    /// </summary>
    private static readonly IEnumerable<string> BuiltinsFunctions = GetDefaultSessionFunctions();

    public override bool ShouldProcess(
        Ast node,
        IEnumerable<Supression> supressions)
    {
        if (node is not CommandAst commandAst) return false;
        if (commandAst.GetCommandName() == null) return false;
        var callName = SanatiseName(commandAst.GetCommandName());

        return !supressions.Any(supression => (string)supression.Data! == callName);
    }

    public override IEnumerable<Issue> Analyse(
        Ast node,
        IEnumerable<Compiled> imports)
    {
        var commandAst = (CommandAst)node;
        var callName = SanatiseName(commandAst.GetCommandName());
        if (BuiltinsFunctions.Contains(callName)) yield break;
        if (AstHelper.FindAvailableFunctions(AstHelper.FindRoot(node), false).Select(definition => SanatiseName(definition.Name)).Any(name => name == callName)) yield break;
        if (imports.Any(module => module.GetExportedFunctions().Contains(callName))) yield break;

        yield return new Issue(
            IssueSeverity.Warning,
            $"Undefined function '{callName}'",
            commandAst.CommandElements[0].Extent,
            commandAst
        );
    }

    public static string SanatiseName(string name)
    {
        var withOutExtension = name.Contains('.') ? name.Split('.').First() : name;
        var withoutScope = withOutExtension.Contains(':') ? withOutExtension.Split(':').Last() : withOutExtension;

        return withoutScope;
    }

    /// <summary>
    /// Get all functions which should always be available in a session.
    /// This will collect the following:
    /// <list type="bullet">
    /// - Builtin functions of powershell
    /// - Functions from modules in the compiling hosts C:\Windows\system32\WindowsPowerShell\v1.0\Modules path.
    /// - Executables in the system32 directory.
    /// - A few manual inclusions to cover some edge cases.
    /// </list>
    /// </summary>
    public static IEnumerable<string> GetDefaultSessionFunctions()
    {
        var defaultFunctions = new List<string>();
        defaultFunctions.AddRange(PowerShell.Create().Runspace.SessionStateProxy.InvokeCommand
            .GetCommands("*", CommandTypes.Application | CommandTypes.Function | CommandTypes.Alias | CommandTypes.Cmdlet, true)
            .Select(command => command.Name));

        var modulesPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "Modules");
        var moduleDirectories = Directory.GetDirectories(modulesPath);
        var ps = PowerShell.Create().AddScript(/*ps1*/ $$"""
            $env:PSModulePath = '{{modulesPath}}';
            $env:Path = "${env:SystemRoot}\system32;${env:SystemRoot};${env:SystemRoot}\System32\Wbem;${env:SystemRoot}\System32\WindowsPowerShell\v1.0\;";
            $PSModuleAutoLoadingPreference = 'All';
            Get-Command * | Select-Object -ExpandProperty Name
        """).Invoke();
        defaultFunctions.AddRange(ps.Select(commandName => ((string)commandName.BaseObject).Replace(".exe", "")));
        return defaultFunctions.Distinct();
    }
}
