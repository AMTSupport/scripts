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
        var script = new ResolvableScript(scriptSpec, parent);

        CompiledScript? compiled = null;
        parent.QueueResolve(script, compiledScript => compiled = compiledScript);
        await parent.Compile();

        Assert.That(compiled, Is.Not.Null);
        var output = compiled!.GetPowerShellObject();

        Assert.Multiple(() => {
            Assert.That(output, Does.Contain("$Script:EMBEDDED_MODULES"));
            Assert.That(output, Does.Contain("$Script:REMOVE_ORDER"));
        });
    }

    [Test]
    public async Task Output_WritesBomAndCrLf() {
        var root = TestUtils.GenerateUniqueDirectory();
        var outputRoot = TestUtils.GenerateUniqueDirectory();
        var filePath = Path.Combine(root, "Root.ps1");
        File.WriteAllText(filePath, "Write-Host 'Hello'\nWrite-Host 'World'");

        Program.Output(root, outputRoot, filePath, "Line1\nLine2", true);
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
