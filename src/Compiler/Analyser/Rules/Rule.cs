using System.Management.Automation.Language;
using Compiler.Module.Compiled;

namespace Compiler.Analyser.Rules;

public abstract class Rule
{
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

    public abstract IEnumerable<Issue> Analyse(
        Ast node,
        IEnumerable<Compiled> imports
    );
}
