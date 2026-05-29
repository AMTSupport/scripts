using System.Collections;
using System.Management.Automation;
using Compiler.Requirements;
using LanguageExt;

namespace Compiler.Module.Resolvable;

public partial class ResolvableLocalModule {
    private Hashtable? PackagedManifest;

    private void ReadPackagedManifestRequirements() {
        var manifest = this.GetPackagedManifest();

        if (manifest["PowerShellVersion"] is string psVersion && Version.TryParse(psVersion, out var psVersionValue)) {
            lock (this.Requirements) {
                this.Requirements.AddRequirement(new PSVersionRequirement(psVersionValue));
            }
        }

        if (manifest["RequiredModules"] is object[] requiredModules) {
            foreach (var requiredModule in requiredModules) {
                if (requiredModule is string moduleName && !string.IsNullOrWhiteSpace(moduleName)) {
                    lock (this.Requirements) {
                        this.Requirements.AddRequirement(new ModuleSpec(moduleName));
                    }

                    continue;
                }

                if (requiredModule is not Hashtable requiredModuleTable) continue;

                var tableModuleName = requiredModuleTable["ModuleName"]?.ToString();
                if (string.IsNullOrWhiteSpace(tableModuleName)) continue;

                _ = Version.TryParse(requiredModuleTable["ModuleVersion"]?.ToString(), out var minimumVersion);
                _ = Version.TryParse(requiredModuleTable["MaximumVersion"]?.ToString(), out var maximumVersion);
                _ = Version.TryParse(requiredModuleTable["RequiredVersion"]?.ToString(), out var requiredVersion);
                _ = Guid.TryParse(requiredModuleTable["GUID"]?.ToString(), out var guid);

                lock (this.Requirements) {
                    this.Requirements.AddRequirement(new ModuleSpec(tableModuleName, guid == Guid.Empty ? null : guid, minimumVersion, maximumVersion, requiredVersion));
                }
            }
        }
    }

    private Hashtable GetPackagedManifest() {
        if (this.PackagedManifest != null) return this.PackagedManifest;

        var manifestPath = this.ModuleSpec.FullPath;
        var manifestResult = Program.RunPowerShell($"Import-PowerShellDataFile -LiteralPath '{manifestPath.Replace("'", "''")}'");
        this.PackagedManifest = manifestResult.Match(
            Succ: objects => (Hashtable)objects[0].BaseObject,
            Fail: _ => []
        );

        return this.PackagedManifest;
    }
}
