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

    private static readonly HashSet<string> Cache = [];

    public static void Analyse(CompiledLocalModule module, IEnumerable<Compiled> availableImports)
    {
        var key = module.ComputedHash;
        if (availableImports.Any()) key += availableImports.Select(x => x.ComputedHash).Aggregate((x, y) => x + y);

        lock (Cache)
        {
            if (Cache.Contains(key)) return;
        }

        Logger.Trace($"Analyzing module {module.ModuleSpec.Name}");

        var visitor = new RuleVisitor(Rules, availableImports);
        module.Ast.Visit(visitor);
        visitor.Issues.ForEach(Program.Issues.Add);

        lock (Cache)
        {
            Cache.Add(key);
        }
    }
}
