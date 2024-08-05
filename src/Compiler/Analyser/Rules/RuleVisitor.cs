using System.Management.Automation.Language;
using Compiler.Module.Compiled;

namespace Compiler.Analyser.Rules;

public sealed class RuleVisitor(
    IEnumerable<Rule> rules,
    IEnumerable<Compiled> imports) : AstVisitor
{
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

    public IEnumerable<Supression> GetSupressions(Ast ast)
    {
        var paramBlock = AstHelper.FindClosestParamBlock(ast);
        if (paramBlock == null) yield break;

        foreach (var attribute in paramBlock.Attributes)
        {
            if (attribute.TypeName.Name != "SuppressAnalyser") continue;

            var justification = string.Empty;
            Type? type = null;
            object? data = null;

            foreach (var arg in attribute.NamedArguments)
            {
                var lowerArgName = arg.ArgumentName.ToLower();
                if (lowerArgName == "justification")
                {
                    justification = (string)arg.Argument.SafeGetValue();
                    continue;
                }

                if (lowerArgName == "checktype")
                {
                    type = _rules.First(rule => rule.GetType().Name == (string)arg.Argument.SafeGetValue()).GetType();
                    continue;
                }

                if (lowerArgName == "data")
                {
                    data = arg.Argument.SafeGetValue();
                    continue;
                }

                throw new NotImplementedException($"Unknown argument {arg.ArgumentName}/{lowerArgName}");
            }

            if (type == null) throw new NotImplementedException("Type is required for a suppression");

            yield return new Supression(justification, type, data);
        }
    }
}
