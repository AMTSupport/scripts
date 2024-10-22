// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation;
using System.Management.Automation.Language;
using Compiler.Module.Compiled;

namespace Compiler.Analyser.Rules;

/// <summary>
/// Ensures that the script contains a param block with the CmdletBinding Attribute at the top level.
/// </summary>
public class MissingCmdlet : Rule {
    public override bool SupportsModule<T>(T compiledModule) => compiledModule is CompiledScript;

    public override bool ShouldProcess(
        Ast node,
        IEnumerable<Suppression> supressions
    ) => node is ScriptBlockAst scriptBlockAst && scriptBlockAst.Parent == null;

    public override IEnumerable<Issue> Analyse(
        Ast node,
        IEnumerable<Compiled> importedModules
    ) {
        var scriptBlockAst = (ScriptBlockAst)node;
        if (scriptBlockAst.ParamBlock != null && scriptBlockAst.ParamBlock.Attributes.Count > 0 && scriptBlockAst.ParamBlock.Attributes.Any(attribute => attribute.TypeName.GetReflectionType() == typeof(CmdletBindingAttribute))) {
            yield break;
        }

        yield return Issue.Error(
            "Missing Top Level Script Paramter Block with [CmdletBinding] Attribute",
            scriptBlockAst.Extent,
            scriptBlockAst
        );
    }
}
