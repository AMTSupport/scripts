using System.Reflection;
using Compiler.Module.Compiled;
using Compiler.Module.Resolvable;
using Compiler.Requirements;
using Compiler.Text;
using LanguageExt;

namespace Compiler.Tests.Module.Compiled;

public class ScriptTests {
    [Test]
    public void Constructor_embeds_runtime_module_without_throwing() {
        using var temp = new TempFolder();
        var sourceRoot = temp.Path;
        var scriptPath = Path.Combine(sourceRoot, "src/automation/Test.ps1");
        Directory.CreateDirectory(Path.GetDirectoryName(scriptPath)!);
        File.WriteAllText(scriptPath, "param()\n");

        var document = CompiledDocument.FromBuilder(new TextEditor(new TextDocument(["param()"])), 0).ThrowIfFail();
        var spec = new PathedModuleSpec(sourceRoot, scriptPath);
        var requirements = new RequirementGroup();

        var script = new CompiledScript(spec, document, requirements) {
            ResolvableParent = new ResolvableParent(sourceRoot)
        };

        var output = script.GetPowerShellObject().ThrowIfFail();
        Assert.That(output, Does.Contain("$RUNTIME_MODULE"));
    }

    [Test]
    public void GetPowerShellObject_includes_runtime_module_replacements() {
        using var temp = new TempFolder();
        var sourceRoot = temp.Path;
        var scriptPath = Path.Combine(sourceRoot, "src/automation/Test.ps1");
        Directory.CreateDirectory(Path.GetDirectoryName(scriptPath)!);
        File.WriteAllText(scriptPath, "param()\n");

        var document = CompiledDocument.FromBuilder(new TextEditor(new TextDocument(["param()"])), 0).ThrowIfFail();
        var spec = new PathedModuleSpec(sourceRoot, scriptPath);
        var requirements = new RequirementGroup();

        var script = new CompiledScript(spec, document, requirements) {
            ResolvableParent = new ResolvableParent(sourceRoot)
        };

        var output = script.GetPowerShellObject().ThrowIfFail();
        Assert.Multiple(() => {
            Assert.That(output, Does.Contain("$RUNTIME_MODULE = "));
            Assert.That(output, Does.Contain("$RUNTIME_MODULE_NAME = 'AMT.PowerShell.Common'"));
        });
    }
}

internal sealed class TempFolder : IDisposable {
    public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), Guid.NewGuid().ToString("N"));

    public TempFolder() => Directory.CreateDirectory(this.Path);

    public void Dispose() {
        if (Directory.Exists(this.Path)) Directory.Delete(this.Path, true);
    }
}
