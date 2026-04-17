// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using Compiler.Text;

namespace Compiler.Test.Text;

[TestFixture]
public partial class DocumentTests {
    private TextEditor Editor;

    [SetUp]
    public void SetUp() {
        this.Editor = new TextEditor(new TextDocument([]));
    }

    [Test]
    public void GetLines_ReturnsSnapshot() {
        var document = new TextDocument(["Line1", "Line2"]);
        var lines = document.GetLines();

        lines[0] = "Changed";

        Assert.That(document.GetLines()[0], Is.EqualTo("Line1"));
    }

    [Test]
    public void GetRequirementsAst_StopsAtRequirementsRegion() {
        var root = TestUtils.GenerateUniqueDirectory();
        var path = TestUtils.GenerateUniqueFile(root, ".ps1", content: "#Requires -Version 5.1\nusing module Test\nWrite-Host 'Hello'");
        var document = new TextDocument(path);
        var ast = document.GetRequirementsAst().ThrowIfFail();

        Assert.That(ast.Extent.Text, Does.Not.Contain("Write-Host"));
    }

    public static partial class TestData;
}
