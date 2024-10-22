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
            GetErrorLocation(scriptBlockAst),
            scriptBlockAst
        );
    }

    /// <summary>
    /// Gets the error location for the issue.
    ///
    /// If the script block has a top level param block, then its extent is returned.
    /// Otherwise an extent covering the location after the using statements,
    /// but before the first command, function or variable assignment is returned.
    /// </summary>
    /// <param name="scriptBlockAst"></param>
    /// <returns></returns>
    private static IScriptExtent GetErrorLocation(ScriptBlockAst scriptBlockAst) {
        if (scriptBlockAst.ParamBlock != null) {
            return scriptBlockAst.ParamBlock.Extent;
        }

        var lastUsing = scriptBlockAst.FindAll(ast => ast is UsingStatementAst, false).LastOrDefault();
        var first = scriptBlockAst.Find(ast => ast is CommandAst or FunctionDefinitionAst or AssignmentStatementAst, false);

        var startingLine = lastUsing?.Extent.EndLineNumber ?? 1;
        var startingColumn = lastUsing?.Extent.StartColumnNumber ?? 1;
        var endingLine = first?.Extent.StartLineNumber ?? scriptBlockAst.Extent.EndLineNumber;
        var endingColumn = first?.Extent.EndColumnNumber ?? scriptBlockAst.Extent.EndColumnNumber;

        var scriptLines = scriptBlockAst.Extent.Text.Split('\n');
        return new ScriptExtent(
            new ScriptPosition(
                scriptBlockAst.Extent.File,
                startingLine,
                startingColumn,
                scriptLines[startingLine - 1],
                scriptBlockAst.Extent.Text
            ),
            new ScriptPosition(
                scriptBlockAst.Extent.File,
                endingLine,
                endingColumn,
                scriptLines[endingLine - 1],
                scriptBlockAst.Extent.Text
            )
        );
    }
}
