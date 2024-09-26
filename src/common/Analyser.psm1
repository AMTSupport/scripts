Using module ./ModuleUtils.psm1;

<#
.SYNOPSIS
    Supplies the SuppressAnalyserAttribute class for suppressing analyser checks,
    this must be supplied so that the analyser can be used in the compiled scripts without,
    encountering errors due to the attribute not being defined.
#>

$CSFilePath = "$PSScriptRoot\..\Compiler\Analyser\Suppression.cs";
if (-not (Get-Variable -Name 'GlobalScript' -Scope Global -ValueOnly) -and (Test-Path -Path $CSFilePath -PathType Leaf)) {
    Add-Type -LiteralPath $CSFilePath;
} else {
    $SuppressionCSharp = @'
using System;

namespace Compiler.Analyser {
    [AttributeUsage(AttributeTargets.All, AllowMultiple = true, Inherited = false)]
    public sealed class SuppressAnalyserAttribute(
        string CheckType,
        object? Data = null,
        string Justification = ''
    ) : Attribute
}
'@;

    Add-Type -TypeDefinition $SuppressionCSharp -Language CSharp;
}

Export-Types -Types @(
    [Compiler.Analyser.SuppressAnalyserAttribute]
)
