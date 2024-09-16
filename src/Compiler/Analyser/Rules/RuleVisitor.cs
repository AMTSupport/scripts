// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation.Language;
using Compiler.Module.Compiled;

namespace Compiler.Analyser.Rules;

public sealed class RuleVisitor(
    Compiled module,
    IEnumerable<Rule> rules,
    IEnumerable<Compiled> imports) : AstVisitor {

    private readonly Compiled Module = module;
    private readonly IEnumerable<Rule> Rules = rules;
    private readonly IEnumerable<Compiled> Imports = imports;

    public readonly List<Issue> Issues = [];

    public override AstVisitAction DefaultVisit(Ast ast) {
        var supressions = GetSupressions(ast);
        foreach (var rule in this.Rules) {
            if (!rule.ShouldProcess(ast, supressions)) continue;
            foreach (var issue in rule.Analyse(ast, this.Imports)) {
                this.Issues.Add(issue.Enrich(this.Module.ModuleSpec));
            }
        }

        return AstVisitAction.Continue;
    }

    public static IEnumerable<Suppression> GetSupressions(Ast ast) {
        var paramBlock = AstHelper.FindClosestParamBlock(ast);
        return paramBlock == null
            ? ([])
            : SuppressAnalyserAttribute.FromAttributes(paramBlock.Attributes).Select(attr => attr.GetSupression());
    }
}
