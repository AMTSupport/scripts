// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections.Concurrent;
using System.Diagnostics.CodeAnalysis;
using System.Diagnostics.Contracts;
using Compiler.Analyser.Rules;
using Compiler.Module.Compiled;
using NLog;

namespace Compiler.Analyser;

public static class Analyser {
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private static readonly IEnumerable<Rule> Rules = [
        new MissingCmdlet(),
        new UseOfUndefinedFunction()
    ];

    private static readonly ConcurrentDictionary<string, Task<List<Issue>>> Cache = [];

    [Pure]
    [return: NotNull]
    public static async Task<List<Issue>> Analyse(CompiledLocalModule module, IEnumerable<Compiled> availableImports) {
        var key = module.ComputedHash[0..8];
        // FIXME - Key orders are not consistent between instances.
        // if (availableImports.Any()) {
        //     var rawBytes = new List<byte>();
        //     availableImports.OrderBy(i => i.ModuleSpec.Name).ToList().ForEach(x => rawBytes.AddRange(Convert.FromHexString(x.ComputedHash)));
        //     key += Convert.ToHexString(SHA256.HashData(rawBytes.ToArray()))[0..8];
        // }

        return await Cache.GetOrAdd(key, _ => Task.Run(() => {
            Logger.Trace($"Analyzing module {module.ModuleSpec.Name}");

            var visitor = new RuleVisitor(Rules, availableImports);
            visitor.VisitModule(module);
            return visitor.Issues;
        }));
    }
}
