// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

namespace Compiler.Test.EdgeCases;

[TestFixture]
public class NewlineNormalizationTests {
    [Test]
    public void CrlfInput_DoesNotBecomeCrCrLf() {
        const string input = "Line1\r\nLine2\r\nLine3";
        const string expected = "Line1\r\nLine2\r\nLine3";

        var normalized = NormalizeNewlines(input);

        Assert.That(normalized, Is.EqualTo(expected));
        Assert.That(normalized, Does.Not.Contain("\r\r\n"));
    }

    [Test]
    public void LfOnlyInput_BecomesCrlf() {
        const string input = "Line1\nLine2\nLine3";
        const string expected = "Line1\r\nLine2\r\nLine3";

        var normalized = NormalizeNewlines(input);

        Assert.That(normalized, Is.EqualTo(expected));
    }

    [Test]
    public void MixedNewlines_AllBecomeCrlf() {
        const string input = "Line1\r\nLine2\nLine3\rLine4";
        const string expected = "Line1\r\nLine2\r\nLine3\r\nLine4";

        var normalized = NormalizeNewlines(input);

        Assert.That(normalized, Is.EqualTo(expected));
        Assert.That(normalized, Does.Not.Contain("\r\r"));
        Assert.That(normalized, Does.Not.Contain("\n\n"));
    }

    [Test]
    public void EmptyString_RemainsEmpty() {
        var normalized = NormalizeNewlines("");

        Assert.That(normalized, Is.Empty);
    }

    [Test]
    public void NoNewlines_RemainsUnchanged() {
        const string input = "Single line without newlines";

        var normalized = NormalizeNewlines(input);

        Assert.That(normalized, Is.EqualTo(input));
    }

    [Test]
    public void NormalizationIsIdempotent() {
        const string input = "Line1\nLine2\r\nLine3\rLine4";

        var firstPass = NormalizeNewlines(input);
        var secondPass = NormalizeNewlines(firstPass);
        var thirdPass = NormalizeNewlines(secondPass);

        Assert.Multiple(() => {
            Assert.That(secondPass, Is.EqualTo(firstPass));
            Assert.That(thirdPass, Is.EqualTo(firstPass));
        });
    }

    [Test]
    public void ConsecutiveNewlines_PreservedAsCrlf() {
        const string input = "Line1\n\n\nLine2";
        const string expected = "Line1\r\n\r\n\r\nLine2";

        var normalized = NormalizeNewlines(input);

        Assert.That(normalized, Is.EqualTo(expected));
    }

    [Test]
    public void TrailingNewline_PreservedAsCrlf() {
        const string input = "Content\n";
        const string expected = "Content\r\n";

        var normalized = NormalizeNewlines(input);

        Assert.That(normalized, Is.EqualTo(expected));
    }

    private static string NormalizeNewlines(string content) =>
        content.Replace("\r\n", "\n").Replace("\r", "\n").Replace("\n", "\r\n");
}
