// Copyright (c) 2024, 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

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
        new MissingCmdlet(),
        new UseOfUndefinedFunction()
    ];

    private static readonly ConcurrentDictionary<string, Task<List<Issue>>> Cache = [];

    [Pure]
    [return: NotNull]
    public static async Task<List<Issue>> Analyse(CompiledLocalModule module, IEnumerable<Compiled> availableImports) {
        if (module.ComputedHash().IsErr(out var moduleHashError, out var moduleHash)) {
            return [Issue.Error(moduleHashError.Message, module.Document.Ast.Extent, module.Document.Ast)];
        }

        var key = moduleHash[0..8];
        if (availableImports.Any()) {
            var rawBytes = new List<byte>();
            foreach (var import in availableImports.OrderBy(i => i.ModuleSpec.Name)) {
                if (import.ComputedHash().IsErr(out var importHashError, out var importHash)) {
                    return [Issue.Error(importHashError.Message, module.Document.Ast.Extent, module.Document.Ast)];
                }

                rawBytes.AddRange(Convert.FromHexString(importHash));
            }
            key += Convert.ToHexString(SHA256.HashData([.. rawBytes]))[0..8];
        }

        return await Cache.GetOrAdd(key, _ => Task.Run(() => {
            Logger.Trace($"Analyzing module {module.ModuleSpec.Name}");

            var visitor = new RuleVisitor(Rules, availableImports);
            visitor.VisitModule(module);
            return visitor.Issues;
        }));
    }
}
