// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Reflection;
using Compiler.Module;
using Compiler.Module.Resolvable;
using Compiler.Requirements;
using LanguageExt;
using ResolvableBase = Compiler.Module.Resolvable.Resolvable;

namespace Compiler.Test.Module.Resolvable;

[TestFixture]
public class ResolvableFactoryTests {
    private static string PrepopulateRemoteCache(string moduleName, string moduleVersion) {
        var cachePath = Path.Join(Path.GetTempPath(), "PowerShellGet", moduleName);
        Directory.CreateDirectory(cachePath);

        var nupkgFile = Path.Join(cachePath, $"{moduleName}.{moduleVersion}.nupkg");
        if (!File.Exists(nupkgFile)) {
            var info = Assembly.GetExecutingAssembly().GetName();
            var resource = $"{info.Name}.Resources.{moduleName}.{moduleVersion}.nupkg";
            using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resource)!;
            using var fs = new FileStream(nupkgFile, FileMode.CreateNew, FileAccess.Write);
            stream.CopyTo(fs);
        }

        return nupkgFile;
    }

    [TearDown]
    public void Cleanup() {
        var cachePath = Path.Join(Path.GetTempPath(), "PowerShellGet", "PSReadLine");
        if (Directory.Exists(cachePath)) {
            Directory.Delete(cachePath, true);
        }
    }

    #region TryCreate

    [Test]
    public async Task TryCreate_NoParent_CreatesRemoteModule() {
        PrepopulateRemoteCache("PSReadLine", "2.3.5");
        var spec = new ModuleSpec("PSReadLine", requiredVersion: new Version(2, 3, 5));

        var result = await ResolvableBase.TryCreate(Option<ResolvableBase>.None, spec);

        Assert.That(result.IsOk(out var resolvable, out _), Is.True, "TryCreate should succeed");
        Assert.That(resolvable, Is.InstanceOf<ResolvableRemoteModule>());
    }

    [Test]
    public async Task TryCreate_LocalParent_ValidChild_CreatesLocalModule() {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var parentFile = TestUtils.GenerateUniqueFile(sourceRoot, ".psm1", content: "function Invoke-Parent {}");
        var childFile = Path.Combine(sourceRoot, "Child.psm1");
        await File.WriteAllTextAsync(childFile, "function Invoke-Child {}");

        var parentSpec = new PathedModuleSpec(sourceRoot, parentFile);
        var parent = new ResolvableLocalModule(parentSpec);
        var childSpec = new PathedModuleSpec(sourceRoot, childFile);

        var result = await ResolvableBase.TryCreate(Option<ResolvableBase>.Some(parent), childSpec);

        Assert.That(result.IsOk(out var resolvable, out _), Is.True, "TryCreate should succeed for local child");
        Assert.That(resolvable, Is.InstanceOf<ResolvableLocalModule>());
    }

    [Test]
    public async Task TryCreate_LocalParent_InvalidChild_FallsBackToRemote() {
        PrepopulateRemoteCache("PSReadLine", "2.3.5");
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var parentFile = TestUtils.GenerateUniqueFile(sourceRoot, ".psm1", content: "function Invoke-Parent {}");

        var parentSpec = new PathedModuleSpec(sourceRoot, parentFile);
        var parent = new ResolvableLocalModule(parentSpec);
        var childSpec = new ModuleSpec("PSReadLine", requiredVersion: new Version(2, 3, 5));

        var result = await ResolvableBase.TryCreate(Option<ResolvableBase>.Some(parent), childSpec);

        Assert.That(result.IsOk(out var resolvable, out _), Is.True, "TryCreate should fall back to remote");
        Assert.That(resolvable, Is.InstanceOf<ResolvableRemoteModule>());
    }

    [Test]
    public async Task TryCreate_NonLocalParent_CreatesRemoteModule() {
        PrepopulateRemoteCache("PSReadLine", "2.3.5");
        var spec = new ModuleSpec("PSReadLine", requiredVersion: new Version(2, 3, 5));
        var remoteParent = new ResolvableRemoteModule(new ModuleSpec("SomeOtherModule"));

        var result = await ResolvableBase.TryCreate(Option<ResolvableBase>.Some(remoteParent), spec);

        Assert.That(result.IsOk(out var resolvable, out _), Is.True, "TryCreate should create remote when parent is not local");
        Assert.That(resolvable, Is.InstanceOf<ResolvableRemoteModule>());
    }

    [Test]
    public async Task TryCreate_WithMergeSpecs_MergesModuleSpec() {
        PrepopulateRemoteCache("PSReadLine", "2.3.5");
        var baseSpec = new ModuleSpec("PSReadLine", minimumVersion: new Version(2, 0, 0));
        var mergeSpec = new ModuleSpec("PSReadLine", requiredVersion: new Version(2, 3, 5));

        var result = await ResolvableBase.TryCreate(
            Option<ResolvableBase>.None,
            baseSpec,
            new System.Collections.ObjectModel.Collection<ModuleSpec> { mergeSpec }
        );

        Assert.That(result.IsOk(out var resolvable, out _), Is.True, "TryCreate with merge should succeed");
        Assert.That(resolvable, Is.Not.Null);
        Assert.That(resolvable!.ModuleSpec.RequiredVersion, Is.EqualTo(new Version(2, 3, 5)));
    }

    #endregion

    #region TryCreateScript

    [Test]
    public async Task TryCreateScript_ValidScript_Succeeds() {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var scriptFile = Path.Combine(sourceRoot, "Test.ps1");
        await File.WriteAllTextAsync(scriptFile, "Write-Host 'Hello'");

        var moduleSpec = new PathedModuleSpec(sourceRoot, scriptFile);
        var parent = new ResolvableParent(sourceRoot);

        var result = await ResolvableBase.TryCreateScript(moduleSpec, parent);

        Assert.That(result.IsOk(out var script, out _), Is.True, "TryCreateScript should succeed");
        Assert.That(script, Is.InstanceOf<ResolvableScript>());
    }

    [Test]
    public async Task TryCreateScript_NonExistentFile_ReturnsFail() {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var moduleSpec = new PathedModuleSpec(sourceRoot, Path.Combine(sourceRoot, "NonExistent.ps1"));
        var parent = new ResolvableParent(sourceRoot);

        var result = await ResolvableBase.TryCreateScript(moduleSpec, parent);

        Assert.That(result.IsOk(out _, out _), Is.False, "TryCreateScript should fail for nonexistent file");
    }

    #endregion
}

[TestFixture]
public class ResolvableParentMergeTests {
    private static string PrepopulateRemoteCache(string moduleName, string moduleVersion) {
        var cachePath = Path.Join(Path.GetTempPath(), "PowerShellGet", moduleName);
        Directory.CreateDirectory(cachePath);

        var nupkgFile = Path.Join(cachePath, $"{moduleName}.{moduleVersion}.nupkg");
        if (!File.Exists(nupkgFile)) {
            var info = Assembly.GetExecutingAssembly().GetName();
            var resource = $"{info.Name}.Resources.{moduleName}.{moduleVersion}.nupkg";
            using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resource)!;
            using var fs = new FileStream(nupkgFile, FileMode.CreateNew, FileAccess.Write);
            stream.CopyTo(fs);
        }

        return nupkgFile;
    }

    [TearDown]
    public void Cleanup() {
        var cachePath = Path.Join(Path.GetTempPath(), "PowerShellGet", "PSReadLine");
        if (Directory.Exists(cachePath)) {
            Directory.Delete(cachePath, true);
        }
    }

    [Test]
    public async Task LinkFindingPossibleResolved_NewModule_AddsToGraph() {
        PrepopulateRemoteCache("PSReadLine", "2.3.5");
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var parent = new ResolvableParent(sourceRoot);

        var spec = new ModuleSpec("PSReadLine", requiredVersion: new Version(2, 3, 5));
        var result = await parent.LinkFindingPossibleResolved(null, spec);

        Assert.That(result.IsOk(out var optResolvable, out _), Is.True, "LinkFindingPossibleResolved should succeed");
        Assert.That(optResolvable.IsSome, Is.True, "Should return Some resolvable");
        Assert.That(parent.Graph.VertexCount, Is.EqualTo(1));
    }

    [Test]
    public async Task LinkFindingPossibleResolved_ExistingModule_SameMatch_ReusesVertex() {
        PrepopulateRemoteCache("PSReadLine", "2.3.5");
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var parent = new ResolvableParent(sourceRoot);

        var spec = new ModuleSpec("PSReadLine", requiredVersion: new Version(2, 3, 5));
        var firstResult = await parent.LinkFindingPossibleResolved(null, spec);
        Assert.That(firstResult.IsOk(out _, out _), Is.True);

        var scriptFile = Path.Combine(sourceRoot, "Script.ps1");
        await File.WriteAllTextAsync(scriptFile, "Write-Host 'test'");
        var scriptSpec = new PathedModuleSpec(sourceRoot, scriptFile);
        var scriptResolvable = new ResolvableLocalModule(scriptSpec);
        lock (parent.Graph) {
            parent.Graph.AddVertex(scriptResolvable);
        }

        // Link same spec from the script → should reuse existing vertex
        var secondResult = await parent.LinkFindingPossibleResolved(scriptResolvable, spec);
        Assert.That(secondResult.IsOk(out _, out _), Is.True);

        Assert.That(parent.Graph.VertexCount, Is.EqualTo(2));
        Assert.That(parent.Graph.EdgeCount, Is.EqualTo(1));
    }



    [Test]
    public async Task FindResolvable_ReturnsNone_WhenEmpty() {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var parent = new ResolvableParent(sourceRoot);
        var spec = new ModuleSpec("NonExistent");

        var result = parent.FindResolvable(spec);

        Assert.That(result.IsNone, Is.True);
    }

    [Test]
    public async Task FindResolvable_ReturnsSome_WhenModuleExists() {
        PrepopulateRemoteCache("PSReadLine", "2.3.5");
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var parent = new ResolvableParent(sourceRoot);

        var spec = new ModuleSpec("PSReadLine", requiredVersion: new Version(2, 3, 5));
        await parent.LinkFindingPossibleResolved(null, spec);

        var result = parent.FindResolvable(spec);

        Assert.That(result.IsSome, Is.True);
    }

    [Test]
    public void QueueResolve_AddsToGraphAndResolvables() {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var parent = new ResolvableParent(sourceRoot);

        var scriptFile = TestUtils.GenerateUniqueFile(sourceRoot, ".ps1", content: "Write-Host 'test'");
        var scriptSpec = new PathedModuleSpec(sourceRoot, scriptFile);
        var resolvable = new ResolvableLocalModule(scriptSpec);

        parent.QueueResolve(resolvable);

        Assert.Multiple(() => {
            Assert.That(parent.Graph.ContainsVertex(resolvable), Is.True);
            Assert.That(parent.Resolvables.ContainsKey(resolvable.ModuleSpec), Is.True);
        });
    }
}
