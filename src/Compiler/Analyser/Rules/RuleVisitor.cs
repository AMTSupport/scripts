// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation.Language;
using Compiler.Module.Compiled;

namespace Compiler.Analyser.Rules;

public sealed class RuleVisitor(
    IEnumerable<Rule> rules,
    IEnumerable<Compiled> imports) : AstVisitor {
    private readonly IEnumerable<Rule> _rules = rules;
    private readonly IEnumerable<Compiled> _imports = imports;

    public readonly List<Issue> Issues = [];

    public override AstVisitAction DefaultVisit(Ast ast) {
        var supressions = GetSupressions(ast);
        foreach (var rule in this._rules) {
            if (!rule.ShouldProcess(ast, supressions)) continue;
            this.Issues.AddRange(rule.Analyse(ast, this._imports));
        }

        return AstVisitAction.Continue;
    }

    public static IEnumerable<Suppression> GetSupressions(Ast ast) {
        var paramBlock = AstHelper.FindClosestParamBlock(ast);
        return paramBlock == null
            ? (IEnumerable<Suppression>)([])
            : SuppressAnalyserAttribute.FromAttributes(paramBlock.Attributes).Select(attr => attr.GetSupression());
    }
}
