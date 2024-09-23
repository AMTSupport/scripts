// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using Compiler.Text.Updater.Built;

namespace Compiler.Test.Text.Updater.Built;

[TestFixture]
public class CommentRemovalUpdaterTests {
    [TestCaseSource(typeof(TestData), nameof(TestData.Data))]
    public string Apply_RemovesComments(string content) {
        var updater = new CommentRemovalUpdater();
        var lines = content.Split('\n').ToList();
        var result = updater.Apply(lines);

        Assert.Multiple(() => {
            Assert.That(lines, Is.Not.Null);
            Assert.That(result, Is.Not.Null.Or.Empty);
            Assert.That(result.IsSucc, Is.True);
        });

        return string.Join('\n', lines);
    }

    private static class TestData {
        public static IEnumerable Data {
            get {
                yield return new TestCaseData("""
                Write-Host 'Hello, World!'# This is a comment
                """).Returns("""
                Write-Host 'Hello, World!'
                """);

                yield return new TestCaseData("""
                Write-Host 'Hello, World!'# This is a comment
                Write-Host 'Goodbye, World!'# This is another comment
                """).Returns("""
                Write-Host 'Hello, World!'
                Write-Host 'Goodbye, World!'
                """);

                yield return new TestCaseData("""
                Write-Host 'Hello, World!'# This is a comment
                # This is another comment
                """).Returns("""
                Write-Host 'Hello, World!'
                """);

                yield return new TestCaseData("""
                # This is a comment
                # This is another comment
                """).Returns(string.Empty);

                yield return new TestCaseData("""
                # This is a comment
                """).Returns(string.Empty);

                yield return new TestCaseData("""
                Write-Host 'Hello, World!'
                """).Returns("""
                Write-Host 'Hello, World!'
                """);
            }
        }
    }
}
