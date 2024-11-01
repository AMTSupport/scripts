// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using Compiler.Module.Compiled;

namespace Compiler.Test.Module.Compiled;

[TestFixture]
public sealed class CompiledScriptTests {
    [Test]
    public void GetRootParent_ReturnsSelf() {
        var module = CompiledLocalModuleTests.TestData.CreateModule<CompiledScript>();
        Assert.That(module.GetRootParent(), Is.EqualTo(module));
    }
}
