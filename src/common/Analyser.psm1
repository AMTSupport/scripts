Using module .\ModuleUtils.psm1

<#
.SYNOPSIS
    Supplies the SuppressAnalyserAttribute class for suppressing analyser checks,
    this must be supplied so that the analyser can be used in the compiled scripts without,
    encountering errors due to the attribute not being defined.
#>

$CSFilePath = "$PSScriptRoot\..\Compiler\Analyser\Suppression.cs";
if ($PSVersionTable.PSVersion.Major -ge 6 -and -not (Get-Variable -Name 'CompiledScript' -Scope Global -ValueOnly -ErrorAction SilentlyContinue) -and (Test-Path -Path $CSFilePath -PathType Leaf)) {
    Add-Type -LiteralPath $CSFilePath;
} else {
    $SuppressionCSharp = @'
using System;

namespace Compiler.Analyser {
    [AttributeUsage(AttributeTargets.All, AllowMultiple = true, Inherited = false)]
    public sealed class SuppressAnalyserAttribute : Attribute {
        public readonly string CheckType;
        public readonly object Data;
        public string Justification;

        public SuppressAnalyserAttribute(
            string CheckType,
            object Data
        ) {
            this.CheckType = CheckType;
            this.Data = Data;
        }
    }
}
'@;

    Add-Type -TypeDefinition $SuppressionCSharp -Language CSharp -IgnoreWarnings -WarningAction SilentlyContinue;
}

Export-Types -Types @(
    [Compiler.Analyser.SuppressAnalyserAttribute]
)
