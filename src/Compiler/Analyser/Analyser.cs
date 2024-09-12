// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections.Concurrent;
using System.Diagnostics.CodeAnalysis;
using System.Diagnostics.Contracts;
using System.Security.Cryptography;
using Compiler.Analyser.Rules;
using Compiler.Module.Compiled;
using NLog;

namespace Compiler.Analyser;

public static class Analyser {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private static readonly IEnumerable<Rule> Rules = [
        new UseOfUndefinedFunction()
    ];

    private static readonly ConcurrentBag<string> Cache = [];

    [Pure]
    [return: NotNull]
    public static List<Issue> Analyse(CompiledLocalModule module, IEnumerable<Compiled> availableImports) {
        var key = module.ComputedHash[0..8];
        if (availableImports.Any()) {
            var rawBytes = new List<byte>();
            availableImports.ToList().ForEach(x => rawBytes.AddRange(Convert.FromHexString(x.ComputedHash)));
            key += Convert.ToHexString(SHA256.HashData(rawBytes.ToArray()))[0..8];
        }

        if (Cache.Contains(key)) {
            Logger.Trace($"Cache hit for {module.ModuleSpec.Name} with key {key}");
            return [];
        }

        Logger.Trace($"Analyzing module {module.ModuleSpec.Name}");

        var visitor = new RuleVisitor(module, Rules, availableImports);
        module.Document.Ast.Visit(visitor);

        Logger.Trace($"Caching analysis for {module.ModuleSpec.Name} with key {key}");
        Cache.Add(key);

        return visitor.Issues;
    }
}
