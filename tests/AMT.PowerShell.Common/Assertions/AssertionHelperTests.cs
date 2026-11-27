// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using AMT.PowerShell.Common.Assertions;

namespace AMT.PowerShell.Common.Tests.Assertions;

[TestFixture]
public sealed class AssertionHelperTests {
    [Test]
    public void IsNotNull_ReturnsFalseForNull() {
        Assert.That(AssertionHelper.IsNotNull(null), Is.False);
    }

    [Test]
    public void IsNotNull_ReturnsTrueForValue() {
        Assert.That(AssertionHelper.IsNotNull("value"), Is.True);
    }

    [Test]
    public void AreEqual_UsesPowerShellEqualitySemantics() {
        Assert.Multiple(() => {
            Assert.That(AssertionHelper.AreEqual("alpha", "ALPHA"), Is.True);
            Assert.That(AssertionHelper.AreEqual(1, "1"), Is.True);
            Assert.That(AssertionHelper.AreEqual("alpha", "beta"), Is.False);
        });
    }
}
