// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation;
using System.Management.Automation.Language;
using Compiler.Module.Compiled;

namespace Compiler.Analyser.Rules;

/// <summary>
/// Ensures that the script contains a param block with the CmdletBinding Attribute at the top level.
///
/// This is applied to all scripts as a general rule, however is only important to scripts using the
/// Invoke-RunMain $PSCmdlet function due to the usage of the $PSCmdlet object.
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
    /// If the script usage of the $PSCmdlet object with the Invoke-RunMain function, then that extent is returned.
    /// If an extent covering the location after the using statements, but before the first command, function or variable assignment is returned.
    /// </summary>
    /// <param name="scriptBlockAst"></param>
    /// <returns></returns>
    private static IScriptExtent GetErrorLocation(ScriptBlockAst scriptBlockAst) {
        if (scriptBlockAst.ParamBlock != null) {
            return scriptBlockAst.ParamBlock.Extent;
        }

        // Find the usage of the $PSCmdlet object

        if (scriptBlockAst.Find(ast => ast is CommandAst commandAst
            && (string)commandAst.CommandElements[0].SafeGetValue() == "Invoke-RunMain", false)
            is CommandAst invokeRunMain
        ) {
            // If there are named arguments look for the -Cmdlet parameter, otherwise get the first argument
            var cmdletArgument = invokeRunMain.Find(ast => ast is CommandParameterAst commandParameterAst && commandParameterAst.ParameterName == "Cmdlet", false)
                ?? invokeRunMain.CommandElements[1];

            return cmdletArgument.Extent;
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
