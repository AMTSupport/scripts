// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using System.Management.Automation.Language;
using Compiler.Module.Compiled;
using LanguageExt;

namespace Compiler.Analyser.Rules;

public sealed class RuleVisitor(
    IEnumerable<Rule> rules,
    IEnumerable<Compiled> imports) : AstVisitor {

    private readonly IEnumerable<Rule> Rules = rules;
    private readonly IEnumerable<Compiled> Imports = imports;
    private readonly Dictionary<int, Dictionary<Rule, bool>> ThreadLocalCache = [];
    public readonly List<Issue> Issues = [];

    public void VisitModule([NotNull] CompiledLocalModule compiledModule) {
        this.ThreadLocalCache.Add(Environment.CurrentManagedThreadId, []);
        foreach (var rule in this.Rules) {
            this.ThreadLocalCache[Environment.CurrentManagedThreadId].Add(rule, rule.SupportsModule(compiledModule));
        }

        compiledModule.Document.Ast.Visit(this);
        this.ThreadLocalCache.Remove(Environment.CurrentManagedThreadId);
    }

    public override AstVisitAction DefaultVisit(Ast ast) {
        if (GetSupressions(ast).IsErr(out var err, out var suppressions)) {
            if (err is Issue issue) {
                this.Issues.Add(issue);
            } else if (err is ManyErrors errors) {
                this.Issues.AddRange(errors.Errors.Cast<Issue>());
            }

            return AstVisitAction.SkipChildren;
        }

        foreach (var rule in this.Rules) {
            // If the key doesn't exist assume we support it, this allows for usage outside of the visitor like in tests.
            if (this.ThreadLocalCache.TryGetValue(Environment.CurrentManagedThreadId, out var threadCache)
                && threadCache.TryGetValue(rule, out var supports)
                && !supports
            ) continue;

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
            : SuppressAnalyserAttributeExt.FromAttributes(paramBlock.Attributes)
                .Map(suppressions => suppressions.Select(suppression => suppression.GetSuppression()));
    }
}
