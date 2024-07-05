using System.Management.Automation;
using System.Management.Automation.Language;
using System.Text;
using Compiler.Module;
using NLog;
using Pastel;

namespace Compiler.Analyser;

public static class StaticAnalyser
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    /*
        A list of all the built-in functions that are provided in a standard session.
        This includes modules that are imported by default.
    */
    private static readonly IEnumerable<string> BuiltinsFunctions = GetDefaultSessionFunctions();

    public static void Analyse(CompiledModule module, IEnumerable<CompiledModule> availableImports)
    {
        Logger.Trace($"Analyzing module {module.PreCompileModuleSpec.Name}");

        var undefinedFunctions = FindUndefinedFunctions(module, availableImports);
        if (undefinedFunctions.Count > 0)
        {
            foreach (var undefinedFunction in undefinedFunctions)
            {
                // Logger.Error($"Undefined function: {undefinedFunction.GetCommandName()}");
                // Logger.Error($"Location: {undefinedFunction.Extent.File}({undefinedFunction.Extent.StartLineNumber},{undefinedFunction.Extent.StartColumnNumber})");
                PrintPrettyAstError(undefinedFunction, "Undefined function found in module.");
            }
            throw new Exception("Undefined functions found in module.");
        }
    }

    /*
        Get all functions which should always be available in a session.
        This will collect the builtin functions of powershell as-well,
        as well as the functions from modules in the compiling hosts C:\Windows\system32\WindowsPowerShell\v1.0\Modules path.
    */
    public static IEnumerable<string> GetDefaultSessionFunctions()
    {
        var defaultFunctions = new List<string>();
        defaultFunctions.AddRange(PowerShell.Create().Runspace.SessionStateProxy.InvokeCommand
            .GetCommands("*", CommandTypes.Function | CommandTypes.Alias | CommandTypes.Cmdlet, true)
            .Select(command => command.Name));

        var modulesPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "Modules");
        if (!Directory.Exists(modulesPath))
        {
            return defaultFunctions;
        }

        var moduleDirectories = Directory.GetDirectories(modulesPath);
        var ps = PowerShell.Create().AddScript(/*ps1*/ $$"""
            $env:PSModulePath = '{{modulesPath}}';
            $PSModuleAutoLoadingPreference = 'All';
            Get-Command | Select-Object -ExpandProperty Name -Unique
        """).Invoke();

        foreach (var commandName in ps)
        {
            defaultFunctions.Add((string)commandName.BaseObject);
        }

        return defaultFunctions;
    }

    public static List<CommandAst> FindUndefinedFunctions(CompiledModule module, IEnumerable<CompiledModule> availableImports)
    {
        var calledFunctions = AstHelper.FindCalledFunctions(module.ModuleAst);
        var availableFunctions = new List<string>();
        availableFunctions.AddRange(AstHelper.FindAvailableFunctions(module.ModuleAst, false).Select(definition => definition.Name));
        availableFunctions.AddRange(availableImports.SelectMany(module => module.GetExportedFunctions()));
        var combinedFunctions = availableFunctions.Concat(BuiltinsFunctions).ToList();
        var unknownCalls = calledFunctions.Where(func => !combinedFunctions.Any(availableFunc => availableFunc == func.GetCommandName()));

        return unknownCalls.ToList();
    }

    // TODO, ability to translate the virtual cleaned line numbers to the actual line numbers in the file.
    public static void PrintPrettyAstError(Ast ast, string message)
    {
        var startingLine = ast.Extent.StartLineNumber;
        var endingLine = ast.Extent.EndLineNumber;

        var firstColumnIndent = Math.Max(endingLine.ToString().Length + 1, 5);
        var firstColumnIndentString = new string(' ', firstColumnIndent);
        var colouredPipe = "|".Pastel(ConsoleColor.Cyan);

        var rootParent = ast.Parent;
        do
        {
            rootParent = rootParent.Parent;
        } while (rootParent.Parent != null);
        var extentRegion = rootParent.Extent.Text.Split('\n')[(startingLine - 1)..endingLine];

        var printableLines = new string[extentRegion.Length];
        for (var i = 0; i < extentRegion.Length; i++)
        {
            var line = extentRegion[i];
            line = i switch
            {
                0 => string.Concat(line[0..(ast.Extent.StartColumnNumber - 1)], line[(ast.Extent.StartColumnNumber - 1)..].Pastel(ConsoleColor.DarkRed)),
                var _ when i == extentRegion.Length - 1 => string.Concat(line[0..(ast.Extent.EndColumnNumber - 1)].Pastel(ConsoleColor.DarkRed), line[(ast.Extent.EndColumnNumber - 1)..]),
                _ => line.Pastel(ConsoleColor.DarkRed)
            };

            var sb = new StringBuilder()
                .Append((i + startingLine).ToString().PadRight(firstColumnIndent).Pastel(ConsoleColor.Cyan))
                .Append(colouredPipe)
                .Append(' ')
                .Append(line);

            printableLines[i] = sb.ToString();
        }

        var longestLine = extentRegion.Max(line => line.TrimEnd().Length);
        var leastWhitespaceBeforeText = extentRegion.Min(line => line.Length - line.TrimStart().Length);
        var errorSquigleLength = longestLine - leastWhitespaceBeforeText;
        var errorPointer = string.Concat([new(' ', leastWhitespaceBeforeText), new('~', errorSquigleLength)]);

        Console.WriteLine($"""
        {"File".PadRight(firstColumnIndent).Pastel(ConsoleColor.Cyan)}{colouredPipe} {rootParent.Extent.File.Pastel(ConsoleColor.Gray)}
        {"Line".PadRight(firstColumnIndent).Pastel(ConsoleColor.Cyan)}{colouredPipe}
        {string.Join('\n', printableLines)}
        {firstColumnIndentString}{colouredPipe} {errorPointer.Pastel(ConsoleColor.DarkRed)}
        {firstColumnIndentString}{colouredPipe} {message.Pastel(ConsoleColor.DarkRed)}
        """);
    }
}
