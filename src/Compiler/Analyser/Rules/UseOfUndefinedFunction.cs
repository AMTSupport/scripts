// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation;
using System.Management.Automation.Language;
using System.Management.Automation.Runspaces;
using Compiler.Module.Compiled;
using NLog;

namespace Compiler.Analyser.Rules;

public class UseOfUndefinedFunction : Rule {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    /// <summary>
    /// A list of all the built-in functions that are provided in a standard session.
    /// This includes modules that are imported by default.
    /// </summary>
    private static readonly IEnumerable<string> BuiltinsFunctions = GetDefaultSessionFunctions();

    public override bool ShouldProcess(
        Ast node,
        IEnumerable<Suppression> supressions) {
        if (node is not CommandAst commandAst) return false;
        if (commandAst.GetCommandName() == null) return false;
        var callName = SanatiseName(commandAst.GetCommandName());

        return !supressions.Any(supression => {
            switch (supression.Data) {
                case IEnumerable<string> functions:
                    return functions.Any(function => function.Equals(callName, StringComparison.OrdinalIgnoreCase));
                case string function:
                    return function == callName;
                default:
                    Logger.Warn($"Supression data is not a string or IEnumerable<string> for rule {this.GetType().Name}");
                    return false;
            }
        });
    }

    public override IEnumerable<Issue> Analyse(
        Ast node,
        IEnumerable<Compiled> importedModules) {
        var commandAst = (CommandAst)node;
        var callName = SanatiseName(commandAst.GetCommandName());

        if (BuiltinsFunctions.Contains(callName)) yield break;
        if (AstHelper.FindAvailableFunctions(AstHelper.FindRoot(node), false).Select(definition => SanatiseName(definition.Name)).Contains(callName)) yield break;
        if (AstHelper.FindAvailableAliases(AstHelper.FindRoot(node), false).Select(SanatiseName).Contains(callName)) yield break;
        if (importedModules.Any(module => module.GetExportedFunctions().Select(SanatiseName).Contains(callName))) yield break;

        yield return Issue.Warning(
            $"Undefined function '{commandAst.GetCommandName()}'",
            commandAst.CommandElements[0].Extent,
            commandAst
        );
    }

    public static string SanatiseName(string name) {
        var withOutExtension = name.Contains('.') ? name.Split('.').First() : name;
        var withoutScope = withOutExtension.Contains(':') ? withOutExtension.Split(':').Last() : withOutExtension;

        return withoutScope.ToLowerInvariant();
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
    public static IEnumerable<string> GetDefaultSessionFunctions() {
        var defaultFunctions = new List<string>();

        var sessionState = InitialSessionState.CreateDefault();
        var pwsh = PowerShell.Create(sessionState);
        defaultFunctions.AddRange(pwsh.Runspace.SessionStateProxy.InvokeCommand
            .GetCommands("*", CommandTypes.All, true)
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
        return defaultFunctions.Distinct().Select(SanatiseName);
    }
}
