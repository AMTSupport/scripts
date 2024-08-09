using System.Management.Automation.Language;
using Compiler.Module.Compiled;
using NLog;

namespace Compiler.Analyser.Rules;

public sealed class RuleVisitor(
    IEnumerable<Rule> rules,
    IEnumerable<Compiled> imports) : AstVisitor
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private readonly IEnumerable<Rule> _rules = rules;
    private readonly IEnumerable<Compiled> _imports = imports;

    public readonly List<Issue> Issues = [];

    public override AstVisitAction DefaultVisit(Ast ast)
    {
        var supressions = GetSupressions(ast);
        foreach (var rule in _rules)
        {
            if (!rule.ShouldProcess(ast, supressions)) continue;
            Issues.AddRange(rule.Analyse(ast, _imports));
        }

        return AstVisitAction.Continue;
    }

    public static IEnumerable<Suppression> GetSupressions(Ast ast)
    {
        var paramBlock = AstHelper.FindClosestParamBlock(ast);
        if (paramBlock == null) return [];

        return SuppressAnalyserAttribute.FromAttributes(paramBlock.Attributes).Select(attr => attr.GetSupression());
    }
}
