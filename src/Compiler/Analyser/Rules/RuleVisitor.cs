// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation.Language;
using Compiler.Module.Compiled;
using LanguageExt;

namespace Compiler.Analyser.Rules;

public sealed class RuleVisitor(
    IEnumerable<Rule> rules,
    IEnumerable<Compiled> imports) : AstVisitor {

    private readonly IEnumerable<Rule> Rules = rules;
    private readonly IEnumerable<Compiled> Imports = imports;

    public readonly List<Issue> Issues = [];

    public override AstVisitAction DefaultVisit(Ast ast) {
        if (GetSupressions(ast).IsErr(out var err, out var suppressions)) {
            this.Issues.AddRange(((ManyErrors)err).Errors.Cast<Issue>());
            return AstVisitAction.SkipChildren;
        };

        foreach (var rule in this.Rules) {
            if (!rule.ShouldProcess(ast, suppressions)) continue;
            foreach (var issue in rule.Analyse(ast, this.Imports)) {
                this.Issues.Add(issue);
            }
        }

        return AstVisitAction.Continue;
    }

    public static Fin<IEnumerable<Suppression>> GetSupressions(Ast ast) {
        var paramBlock = AstHelper.FindClosestParamBlock(ast);
        return paramBlock == null
            ? FinSucc(Enumerable.Empty<Suppression>())
            : SuppressAnalyserAttribute.FromAttributes(paramBlock.Attributes)
                .Map(suppressions => suppressions.Select(suppression => suppression.GetSupression()));
    }
}
