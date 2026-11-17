// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

namespace Compiler.Test.Integration;

[TestFixture]
public sealed class RuntimeModuleEmbeddingTests {
    [Test]
    public void CompilerAssemblyContainsRuntimeModuleResources() {
        var asm = typeof(Compiler.Program).Assembly;
        var names = asm.GetManifestResourceNames();

        Assert.That(names, Has.Some.Contains("Resources.RuntimeModule.AMT.PowerShell.Common.dll"));
        Assert.That(names, Has.Some.Contains("Resources.RuntimeModule.AMT.PowerShell.Common.psd1"));
    }
}
