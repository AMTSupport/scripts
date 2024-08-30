// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Diagnostics.CodeAnalysis;
using System.Diagnostics.Contracts;
using Compiler.Analyser.Rules;
using Compiler.Module.Compiled;
using NLog;

namespace Compiler.Analyser;

public static class Analyser {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();


    private static readonly IEnumerable<Rule> Rules = [
        new UseOfUndefinedFunction()
    ];

    private static readonly HashSet<string> Cache = [];

    [Pure]
    [return: NotNull]
    public static List<Issue> Analyse(CompiledLocalModule module, IEnumerable<Compiled> availableImports) {
        var key = module.ComputedHash;
        if (availableImports.Any()) key += availableImports.Select(x => x.ComputedHash).Aggregate((x, y) => x + y);

        lock (Cache) {
            if (Cache.Contains(key)) return [];
        }

        Logger.Trace($"Analyzing module {module.ModuleSpec.Name}");

        var visitor = new RuleVisitor(module, Rules, availableImports);
        module.Document.Ast.Visit(visitor);

        lock (Cache) {
            _ = Cache.Add(key);
        }

        return visitor.Issues;
    }
}
