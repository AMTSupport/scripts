using System.Text;
using Compiler.Module.Compiled;
using Compiler.Module.Resolvable;
using Compiler.Requirements;

namespace Compiler.Test.Integration;

[TestFixture]
public class PipelineTests {
    [Test]
    public async Task CompilePipeline_ProducesEmbeddedModules() {
        var root = TestUtils.GenerateUniqueDirectory();
        var childPath = Path.Combine(root, "Child.psm1");
        var scriptPath = Path.Combine(root, "Root.ps1");

        File.WriteAllText(childPath, "function Invoke-Child { 'Child' }");
        File.WriteAllText(scriptPath, "using module ./Child.psm1\nInvoke-Child");

        var parent = new ResolvableParent(root);
        var scriptSpec = new PathedModuleSpec(root, scriptPath);
        var script = (await Resolvable.TryCreateScript(scriptSpec, parent)).Unwrap();

        CompiledScript? compiled = null;
        parent.QueueResolve(script, compiledScript => { compiled = compiledScript; return Task.CompletedTask; });
        await parent.Compile();

        Assert.That(compiled, Is.Not.Null);
        var output = compiled!.GetPowerShellObject().Unwrap();

        Assert.Multiple(() => {
            Assert.That(output, Does.Contain("$Script:EMBEDDED_MODULES"));
            Assert.That(output, Does.Contain("$Script:REMOVE_ORDER"));
        });
    }

    [Test]
    public async Task CompilePipeline_EmbedsTransitiveRemoteModulesFromLogging() {
        var root = TestUtils.GenerateUniqueDirectory();
        var commonDir = Path.Combine(root, "common");
        Directory.CreateDirectory(commonDir);

        var loggingPath = Path.Combine(commonDir, "Logging.psm1");
        var scriptPath = Path.Combine(root, "Root.ps1");

        File.WriteAllText(loggingPath, "using module @{ ModuleName = 'PSReadLine'; RequiredVersion = '2.3.5' }\nfunction Invoke-Info { param([string]$Message) $Message }");
        File.WriteAllText(scriptPath, "using module ./common/Logging.psm1\nInvoke-Info 'hello'");

        var cachePath = Path.Join(Path.GetTempPath(), "PowerShellGet", "PSReadLine");
        Directory.CreateDirectory(cachePath);
        var nupkgPath = Path.Join(cachePath, "PSReadLine.2.3.5.nupkg");
        if (!File.Exists(nupkgPath)) {
            var info = typeof(PipelineTests).Assembly.GetName();
            var resource = $"{info.Name}.Resources.PSReadLine.2.3.5.nupkg";
            await using var stream = typeof(PipelineTests).Assembly.GetManifestResourceStream(resource)!;
            await using var file = File.Create(nupkgPath);
            await stream.CopyToAsync(file);
        }

        var parent = new ResolvableParent(root);
        var scriptSpec = new PathedModuleSpec(root, scriptPath);
        var script = (await Resolvable.TryCreateScript(scriptSpec, parent)).Unwrap();

        CompiledScript? compiled = null;
        parent.QueueResolve(script, compiledScript => { compiled = compiledScript; return Task.CompletedTask; });
        await parent.Compile();

        Assert.That(compiled, Is.Not.Null);
        var output = compiled!.GetPowerShellObject().Unwrap();

        Assert.Multiple(() => {
            Assert.That(output, Does.Contain("PSReadLine"));
            Assert.That(output, Does.Not.Contain("PSReadLine-000000"));
        });
    }

    [Test]
    public async Task Output_WritesBomAndCrLf() {
        var root = TestUtils.GenerateUniqueDirectory();
        var outputRoot = TestUtils.GenerateUniqueDirectory();
        var filePath = Path.Combine(root, "Root.ps1");
        File.WriteAllText(filePath, "Write-Host 'Hello'\nWrite-Host 'World'");

        await Program.Output(root, outputRoot, filePath, "Line1\nLine2", true);
        await Task.Delay(50);

        var outputPath = Program.GetOutputLocation(root, outputRoot, filePath);
        var bytes = await File.ReadAllBytesAsync(outputPath);
        var content = Encoding.UTF8.GetString(bytes);

        Assert.Multiple(() => {
            Assert.That(bytes[0..3], Is.EqualTo(new[] { (byte)0xEF, (byte)0xBB, (byte)0xBF }));
            Assert.That(content, Does.Contain("\r\n"));
        });
    }
}
