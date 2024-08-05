using Compiler.Analyser.Rules;
using Compiler.Module.Compiled;
using NLog;

namespace Compiler.Analyser;

public static class Analyser
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private static readonly IEnumerable<Rule> Rules = [
        new UseOfUndefinedFunction()
    ];

    public static void Analyse(CompiledLocalModule module, IEnumerable<Compiled> availableImports)
    {
        Logger.Trace($"Analyzing module {module.ModuleSpec.Name}");

        var visitor = new RuleVisitor(Rules, availableImports);
        module.Ast.Visit(visitor);
        visitor.Issues.ForEach(Program.Issues.Add);
    }
}
