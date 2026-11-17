// Copyright (c) 2024, 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using Compiler.Module.Resolvable;
using Compiler.Requirements;

namespace Compiler.Test.Module.Resolvable;

[TestFixture]
public class LocalArchiveModuleTests {
    [Test]
    public async Task ResolveRequirements_LocalPsd1_PreservesFilePathAndSkipsTextPath() {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var moduleDir = Path.Combine(sourceRoot, "Pkg");
        Directory.CreateDirectory(moduleDir);

        var psd1Path = Path.Combine(moduleDir, "Pkg.psd1");
        var psm1Path = Path.Combine(moduleDir, "Pkg.psm1");
        await File.WriteAllTextAsync(psd1Path, @"@{
    ModuleVersion = '1.0.0'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Invoke-Pkg')
    RequiredModules = @(
        'Pester',
        @{ ModuleName = 'ThreadJob'; ModuleVersion = '2.0.3' }
    )
}");
        await File.WriteAllTextAsync(psm1Path, "function Invoke-Pkg { 'Pkg' }");

        var module = new ResolvableLocalModule(new Compiler.Requirements.PathedModuleSpec(sourceRoot, psd1Path));
        var result = await module.ResolveRequirements();
        var compiled = await module.IntoCompiled(new ResolvableParent(sourceRoot));

        Assert.Multiple(() => {
            Assert.That(result.IsNone, Is.True);
            Assert.That(compiled.IsOk(out var value, out _), Is.True);
            Assert.That(value, Is.InstanceOf<Compiler.Module.Compiled.CompiledLocalArchiveModule>());
            Assert.That(value.Type, Is.EqualTo(Compiler.Module.Compiled.ContentType.Zip));
            Assert.That(value.Version, Is.EqualTo(new Version(1, 0, 0)));
            Assert.That(value.GetExportedFunctions(), Does.Contain("Invoke-Pkg"));
            Assert.That(module.Requirements.GetRequirements<Compiler.Requirements.PSVersionRequirement>(), Has.Count.EqualTo(1));
            Assert.That(module.Requirements.GetRequirements<ModuleSpec>().Select(spec => spec.Name), Does.Contain("Pester"));
            Assert.That(module.Requirements.GetRequirements<ModuleSpec>().Select(spec => spec.Name), Does.Contain("ThreadJob"));
        });
    }

    [Test]
    public async Task ResolveRequirements_LocalPsd1_SkipsCompilerInjectedHelperModules() {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var moduleDir = Path.Combine(sourceRoot, "Pkg");
        Directory.CreateDirectory(moduleDir);

        var psd1Path = Path.Combine(moduleDir, "Pkg.psd1");
        await File.WriteAllTextAsync(psd1Path, @"@{
    ModuleVersion = '1.0.0'
    RootModule = 'Pkg.psm1'
    FunctionsToExport = @('Invoke-Pkg')
}");
        await File.WriteAllTextAsync(Path.Combine(moduleDir, "Pkg.psm1"), "function Invoke-Pkg { 'Pkg' }");

        var module = new ResolvableLocalModule(new Compiler.Requirements.PathedModuleSpec(sourceRoot, psd1Path));
        await module.ResolveRequirements();

        Assert.That(module.Requirements.GetRequirements<ModuleSpec>().Select(spec => spec.Name), Does.Not.Contain("Analyser"));
        Assert.That(module.Requirements.GetRequirements<ModuleSpec>().Select(spec => spec.Name), Does.Not.Contain("ModuleUtils"));
    }
}
