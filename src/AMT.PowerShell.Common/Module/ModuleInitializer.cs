using System.Collections;
using System.Management.Automation;
using AMT.PowerShell.Common.Commands.Input;
using AMT.PowerShell.Common.Commands.ModuleUtils;

namespace AMT.PowerShell.Common.Module;

public sealed class ModuleInitializer : IModuleAssemblyInitializer {
    public void OnImport() {
        var validations = new Hashtable(System.StringComparer.OrdinalIgnoreCase) {
            ["Email"] = InputOperations.EmailValidationPattern,
        };

        ScriptBlock.Create("param($value) Set-Variable -Name 'Validations' -Value $value -Scope Global -Force")
            .InvokeReturnAsIs(validations);

        var attributeName = typeof(Compiler.Analyser.SuppressAnalyserAttribute).FullName!;
        if (!TypeAccelerators.Contains(attributeName)) {
            TypeAccelerators.Add(attributeName, typeof(Compiler.Analyser.SuppressAnalyserAttribute));
        }
    }
}
