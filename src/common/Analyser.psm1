Using module ./Utils.psm1

if (-not (Get-Variable -Name 'GlobalScript' -Scope Global -ValueOnly)) {
    Add-Type -LiteralPath $PSScriptRoot\..\Compiler\Analyser\Suppression.cs;
} else {
    $SuppressionCSharp = @'
using System;

namespace Compiler.Analyser {
    [AttributeUsage(AttributeTargets.All, AllowMultiple = true, Inherited = false)]
    public sealed class SuppressAnalyserAttribute(
        string CheckType,
        object Data,
        string Justification = ''
    ) : Attribute
}
'@;

    Add-Type -TypeDefinition $SuppressionCSharp -Language CSharp;
}

Export-Types -Types @(
    [Compiler.Analyser.SuppressAnalyserAttribute]
)
