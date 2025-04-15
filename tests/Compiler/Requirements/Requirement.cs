// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Compiler.Requirements;

namespace Compiler.Test.Requirements;

[TestFixture]
public class RequirementTests {
    [TestCaseSource(typeof(TestData), nameof(TestData.EqualsOperator_Data))]
    public bool EqualsOperator(
        Requirement? requirementOne,
        Requirement? requirementTwo
    ) => requirementOne == requirementTwo;
}

[TestFixture]
public class RequirementWeightSorterTests {
    [Test]
    public void Compare_WhenBothRequirementsAreNull_ReturnsZero() {
        var sorter = new RequirementWeightSorter();
        var result = sorter.Compare(null, null);

        Assert.That(result, Is.EqualTo(0));
    }

    [Test]
    public void Compare_WhenFirstRequirementIsNull_ReturnsNegativeOne() {
        var sorter = new RequirementWeightSorter();
        var requirement = new TestRequirement(true);
        var result = sorter.Compare(null, requirement);

        Assert.That(result, Is.EqualTo(-1));
    }

    [Test]
    public void Compare_WhenSecondRequirementIsNull_ReturnsOne() {
        var sorter = new RequirementWeightSorter();
        var requirement = new TestRequirement(true);
        var result = sorter.Compare(requirement, null);

        Assert.That(result, Is.EqualTo(1));
    }

    [Test]
    public void Compare_WhenBothRequirementsHaveSameWeight_ReturnsZero() {
        var sorter = new RequirementWeightSorter();
        var requirement1 = new TestRequirement(true);
        var requirement2 = new TestRequirement(true);
        var result = sorter.Compare(requirement1, requirement2);

        Assert.That(result, Is.EqualTo(0));
    }

    [Test]
    public void Compare_WhenFirstRequirementHasLowerWeight_ReturnsNegativeOne() {
        var sorter = new RequirementWeightSorter();
        var requirement1 = new TestRequirement(true, 50);
        var requirement2 = new TestRequirement(true, 100);
        var result = sorter.Compare(requirement1, requirement2);

        Assert.That(result, Is.EqualTo(-1));
    }

    [Test]
    public void Compare_WhenFirstRequirementHasHigherWeight_ReturnsOne() {
        var sorter = new RequirementWeightSorter();
        var requirement1 = new TestRequirement(true, 100);
        var requirement2 = new TestRequirement(true, 50);
        var result = sorter.Compare(requirement1, requirement2);

        Assert.That(result, Is.EqualTo(1));
    }

    [Test]
    public void Compare_WhenRequirementsHaveSameWeight_ReturnsZero() {
        var sorter = new RequirementWeightSorter();
        var requirement1 = new TestRequirement(true, hash: [1, 2, 3]);
        var requirement2 = new TestRequirement(true, hash: [1, 2, 4]);
        var result = sorter.Compare(requirement1, requirement2);

        Assert.That(result, Is.EqualTo(0));
    }

    [TestCaseSource(typeof(TestData), nameof(TestData.Compare_Data))]
    public int Compare(
        Requirement requirement1,
        Requirement requirement2
    ) {
        var sorter = new RequirementWeightSorter();
        return sorter.Compare(requirement1, requirement2);
    }
}

file static class TestData {
    public static IEnumerable EqualsOperator_Data {
        get {
            var requirementOne = new TestRequirement(true);
            var requirementTwo = new TestRequirement(false);

            yield return new TestCaseData(requirementOne, requirementOne)
                .SetDescription("Equals true when right is same reference")
                .Returns(true);

            yield return new TestCaseData(requirementOne, requirementTwo)
                .SetDescription("Equals false when right is different")
                .Returns(false);

            yield return new TestCaseData(requirementOne, null)
                .SetDescription("Equals false when right is null")
                .Returns(false);

            yield return new TestCaseData(null, requirementOne)
                .SetDescription("Equals false when left is null")
                .Returns(false);

            yield return new TestCaseData(null, null)
                .SetDescription("Equals true when both are null")
                .Returns(true);

        }
    }

    public static IEnumerable Compare_Data {
        get {
            yield return new TestCaseData(
                new RunAsAdminRequirement(),
                new RunAsAdminRequirement()
            ).Returns(0);

            yield return new TestCaseData(
                new RunAsAdminRequirement(),
                new UsingNamespace("System")
            ).Returns(-1);

            yield return new TestCaseData(
                new UsingNamespace("System"),
                new RunAsAdminRequirement()
            ).Returns(1);

            yield return new TestCaseData(
                new ModuleSpec("TestModule"),
                new PSEditionRequirement(PSEdition.Desktop)
            ).Returns(1);

            yield return new TestCaseData(
                new PSEditionRequirement(PSEdition.Desktop),
                new ModuleSpec("TestModule")
            ).Returns(-1);

            yield return new TestCaseData(
                new ModuleSpec("TestModule"),
                new ModuleSpec("TestModule")
            ).Returns(0);

            yield return new TestCaseData(
                new ModuleSpec("TestModule-2"),
                new ModuleSpec("TestModule-1")
            ).Returns(1);

            yield return new TestCaseData(
                new ModuleSpec("TestModule-1"),
                new ModuleSpec("TestModule-2")
            ).Returns(-1);
        }
    }
}

internal sealed class TestRequirement : Requirement {
    public TestRequirement(
        bool supportsMultiple,
        uint weight = 50,
        byte[]? hash = null) : base() {
        this.SupportsMultiple = supportsMultiple;
        this.Weight = weight;
        this.Hash = hash ?? SHA256.HashData(Encoding.UTF8.GetBytes(weight.ToString(CultureInfo.InvariantCulture)));
    }

    public override string GetInsertableLine(Hashtable data) => throw new NotImplementedException();
    public override bool IsCompatibleWith(Requirement other) => throw new NotImplementedException();
}

internal sealed class SampleRequirement : Requirement {
    public SampleRequirement(string data) : base() {
        this.SupportsMultiple = true;
        this.Hash = SHA256.HashData(Encoding.UTF8.GetBytes(data));
    }

    public override bool IsCompatibleWith(Requirement other) => true;
    public override string GetInsertableLine(Hashtable data) => string.Empty;
}

internal sealed class EasyComparableRequirement : Requirement {
    public EasyComparableRequirement(byte orderInt) : base() {
        this.SupportsMultiple = true;
        this.Hash = [orderInt];
    }

    public override bool IsCompatibleWith(Requirement other) => true;
    public override string GetInsertableLine(Hashtable data) => string.Empty;
}

internal sealed class IncompatibleRequirement : Requirement {
    public IncompatibleRequirement() : base() {
        this.SupportsMultiple = false;
        this.Hash = SHA256.HashData(Encoding.UTF8.GetBytes("Incompatible"));
    }

    public override bool IsCompatibleWith(Requirement other) => false;
    public override string GetInsertableLine(Hashtable data) => string.Empty;
}
