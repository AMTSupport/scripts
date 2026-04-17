// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections.Generic;
using System.Reflection;
using Compiler.Module.Compiled;
using Compiler.Module.Resolvable;
using Compiler.Requirements;
using Compiler.Text;

namespace Compiler.Test.Module.Compiled;

[TestFixture]
public sealed class CompiledScriptTests {
    [Test]
    public void GetRootParent_ReturnsSelf() {
        var module = CompiledLocalModuleTests.TestData.CreateModule<CompiledScript>();
        Assert.That(module.GetRootParent(), Is.EqualTo(module));
    }

    [Test]
    public void GetPowerShellObject_IncludesEmbeddedModulesAndRemoveOrder() {
        var module = CompiledLocalModuleTests.TestData.CreateModule<CompiledScript>("Write-Host 'Root';");
        var dependency = CompiledLocalModuleTests.TestData.CreateModule<CompiledLocalModule>("Write-Host 'Dep';");
        CompiledUtils.AddDependency(module, dependency);

        var output = module.GetPowerShellObject();

        Assert.Multiple(() => {
            Assert.That(output, Does.Contain("$Script:EMBEDDED_MODULES"));
            Assert.That(output, Does.Contain("$Script:REMOVE_ORDER"));
            Assert.That(output, Does.Contain(dependency.GetNameHash()));
        });
    }

    [Test]
    public void GetPowerShellObject_IncludesDefaultParamBlock() {
        var module = CompiledLocalModuleTests.TestData.CreateModule<CompiledScript>("Write-Host 'Root';");
        var output = module.GetPowerShellObject();

        Assert.That(output, Does.Contain("[CmdletBinding()]"));
    }

    [Test]
    public void GetPowerShellObject_AddsErrorWhenDefineMissing() {
        var root = TestUtils.GenerateUniqueDirectory();
        var modulePath = TestUtils.GenerateUniqueFile(root, ".ps1", content: "Write-Host 'Root';");
        var moduleSpec = new PathedModuleSpec(root, modulePath);
        var document = CompiledDocument.FromBuilder(new TextEditor(new TextDocument(["!DEFINE UNKNOWN_TOKEN"]))).Unwrap();
        var module = new CompiledScript(moduleSpec, document, new RequirementGroup()) {
            ResolvableParent = new ResolvableParent(root)
        };

        var output = module.GetPowerShellObject();

        Assert.That(output, Does.Contain("!DEFINE UNKNOWN_TOKEN"));
    }

    [Test]
    public void FillTemplate_MissingDefine_AddsErrorToProgramErrors() {
        var templateWithUnknown = "$x = 1\n# !DEFINE UNKNOWN_TOKEN\nWrite-Host 'hello'";
        var replacements = new Dictionary<string, string>();
        var method = typeof(CompiledScript).GetMethod(
            "FillTemplate",
            BindingFlags.NonPublic | BindingFlags.Static
        )!;

        var errorsBefore = Program.Errors.Count;

        method.Invoke(null, [templateWithUnknown, replacements]);

        Assert.That(Program.Errors, Has.Count.GreaterThan(errorsBefore),
            "Program.Errors should contain an error for each unresolved !DEFINE token");
    }

    [Test]
    public void GetPowerShellObject_WithIsDebugging_IndendsEmbeddedModuleObjects() {
        Program.IsDebugging = true;
        try {
            var module = CompiledLocalModuleTests.TestData.CreateModule<CompiledScript>("Write-Host 'Root';");
            var dependency = CompiledLocalModuleTests.TestData.CreateModule<CompiledLocalModule>("Write-Host 'Dep';");
            CompiledUtils.AddDependency(module, dependency);

            var output = module.GetPowerShellObject();

            Assert.That(output, Does.Contain("        @{"),
                "Embedded module objects should be indented by 8 spaces when Program.IsDebugging is true");
        } finally {
            Program.IsDebugging = false;
        }
    }

    [Test]
    public void GetPowerShellObject_WithTwoDependencies_IncludesBothInEmbeddedModulesAndRemoveOrder() {
        var module = CompiledLocalModuleTests.TestData.CreateModule<CompiledScript>("Write-Host 'Root';");
        var dep1 = CompiledLocalModuleTests.TestData.CreateModule<CompiledLocalModule>("Write-Host 'Dep1';");
        var dep2 = CompiledLocalModuleTests.TestData.CreateModule<CompiledLocalModule>("Write-Host 'Dep2';");
        CompiledUtils.AddDependency(module, dep1);
        CompiledUtils.AddDependency(module, dep2);

        var output = module.GetPowerShellObject();

        Assert.Multiple(() => {
            Assert.That(output, Does.Contain("$Script:EMBEDDED_MODULES"));
            Assert.That(output, Does.Contain("$Script:REMOVE_ORDER"));
            Assert.That(output, Does.Contain(dep1.GetNameHash()),
                "dep1 hash should appear in the output");
            Assert.That(output, Does.Contain(dep2.GetNameHash()),
                "dep2 hash should appear in the output");
            var removeOrderLine = output
                .Split('\n')
                .FirstOrDefault(line => line.Contains("$Script:REMOVE_ORDER"));
            Assert.That(removeOrderLine, Is.Not.Null);
            Assert.That(removeOrderLine, Does.Contain(dep1.GetNameHash()));
            Assert.That(removeOrderLine, Does.Contain(dep2.GetNameHash()));
        });
    }
}
