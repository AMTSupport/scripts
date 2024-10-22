// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation.Language;
using Compiler.Module.Compiled;

namespace Compiler.Analyser.Rules;

public abstract class Rule {
    /// <summary>
    /// Determines if the rule supports the module,
    /// this can be used to determine rules only for the script itself or remote modules etc.
    /// </summary>
    /// <typeparam name="T">The Compiled Module Type</typeparam>
    /// <returns>True if this rule should be applied to the supplied module</returns>
    public abstract bool SupportsModule<T>(T compiledModule) where T : Compiled;

    /// <summary>
    /// Determines if the rule should be processed for this Ast node.
    /// </summary>
    /// <param name="supressions">
    /// A list of suppressions that are relevant to this rule.
    /// </param>
    /// <returns>
    /// True if the rule should be processed, false otherwise.
    /// </returns>
    public abstract bool ShouldProcess(
        Ast node,
        IEnumerable<Suppression> supressions
    );

    /// <summary>
    /// Analyse the Ast node and return any issues found.
    /// </summary>
    /// <param name="node">The AST Node that is being analysed</param>
    /// <param name="importedModules">Any available imports to check against</param>
    /// <returns>A list of issues found</returns>
    public abstract IEnumerable<Issue> Analyse(
        Ast node,
        IEnumerable<Compiled> importedModules
    );
}
