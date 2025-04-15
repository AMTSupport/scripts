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

    public static partial class TestData;
}
