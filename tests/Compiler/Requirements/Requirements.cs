using System.Collections;
using System.Security.Cryptography;
using System.Text;
using Compiler.Requirements;

namespace Compiler.Test.Requirements;

[TestFixture]
public class RequirementsTests
{
    private RequirementGroup Requirements;

    [SetUp]
    public void SetUp()
    {
        Requirements = new RequirementGroup();
    }

    [TestCaseSource(typeof(TestData), nameof(TestData.CaseForEachRequirementType))]
    public void AddRequirement_AddSingleRequirement_ReturnCollection(Requirement requirement)
    {
        Requirements.AddRequirement(requirement);

        Assert.That(Requirements.GetRequirements(), Is.EqualTo(new List<Requirement> { requirement }));
    }

    public static class TestData
    {
        public static IEnumerable CaseForEachRequirementType
        {
            get
            {
                yield return new TestCaseData(new ModuleSpec("TestModule")).SetCategory("ModuleSpec");
                yield return new TestCaseData(new PSEditionRequirement(PSEdition.Desktop)).SetCategory("PSEditionRequirement");
                yield return new TestCaseData(new PSVersionRequirement(new Version(7, 0))).SetCategory("PSVersionRequirement");
                yield return new TestCaseData(new RunAsAdminRequirement()).SetCategory("RunAsAdminRequirement");
            }
        }
    }
}

[TestFixture]
public class RequirementGroupTests
{
    [TestCaseSource(typeof(TestData), nameof(TestData.AddRequirementTests))]
    public void AddRequirement(Requirement[] requirements)
    {
        var requirementGroup = new RequirementGroup();
        foreach (var requirement in requirements)
        {
            requirementGroup.AddRequirement(requirement);
        }

        var storedRequirements = requirementGroup.GetRequirements<Requirement>();
        Assert.Multiple(() =>
        {
            Assert.That(storedRequirements, Has.Count.EqualTo(requirements.Length));
            Assert.That(storedRequirements, Is.EquivalentTo(requirements));
        });
    }

    [TestCaseSource(typeof(TestData), nameof(TestData.AddRequirementTests))]
    public void RemoveRequirement(Requirement[] requirements)
    {
        var requirementGroup = new RequirementGroup();
        foreach (var requirement in requirements)
        {
            requirementGroup.AddRequirement(requirement);
        }

        var removingCount = (int)Math.Ceiling(requirements.Length / 2.0); // Ensure we remove at least one
        var removed = 0;
        for (var i = 0; i < removingCount; i++)
        {
            if (requirementGroup.RemoveRequirement(requirements[i])) removed++;
        }

        var storedRequirements = requirementGroup.GetRequirements<Requirement>();
        Assert.Multiple(() =>
        {
            Assert.That(removed, Is.EqualTo(removingCount));
            Assert.That(storedRequirements, Has.Count.EqualTo(requirements.Length - removed));
            Assert.That(storedRequirements, Is.EquivalentTo(requirements.Skip(removingCount)));
        });
    }

    [Test, Repeat(1000)]
    public void GetRequirements_ShouldReturnAllRequirementsInOrderOfHashWhenSameWeight()
    {
        var requirementGroup = new RequirementGroup();
        var requirementsList = new List<Requirement>();
        for (var i = 0; i < 100; i++)
        {
            var requirement = new TestData.SampleRequirement(i.ToString());
            requirementsList.Add(requirement);
            requirementGroup.AddRequirement(requirement);
        }

        var requirements = requirementGroup.GetRequirements();
        Assert.Multiple(() =>
        {
            Assert.That(requirements, Has.Count.EqualTo(100));
            Assert.That(requirements, Is.Ordered.By(nameof(Requirement.Weight)));
            for (var i = 0; i < 100; i++)
            {
                Assert.That(requirements.ElementAt(i), Is.EqualTo(requirementsList[i]));
            }
        });
    }
}

[TestFixture]
public class RequirementWeightSorterTests
{
    [Test]
    public void Compare_WhenBothRequirementsAreNull_ReturnsZero()
    {
        var sorter = new RequirementWeightSorter();
        int result = sorter.Compare(null, null);

        Assert.That(result, Is.EqualTo(0));
    }

    [Test]
    public void Compare_WhenFirstRequirementIsNull_ReturnsNegativeOne()
    {
        var sorter = new RequirementWeightSorter();
        var requirement = new TestData.TestRequirement(true);
        int result = sorter.Compare(null, requirement);

        Assert.That(result, Is.EqualTo(-1));
    }

    [Test]
    public void Compare_WhenSecondRequirementIsNull_ReturnsOne()
    {
        var sorter = new RequirementWeightSorter();
        var requirement = new TestData.TestRequirement(true);
        int result = sorter.Compare(requirement, null);

        Assert.That(result, Is.EqualTo(1));
    }

    [Test]
    public void Compare_WhenBothRequirementsHaveSameWeight_ReturnsZero()
    {
        var sorter = new RequirementWeightSorter();
        var requirement1 = new TestData.TestRequirement(true);
        var requirement2 = new TestData.TestRequirement(true);
        int result = sorter.Compare(requirement1, requirement2);

        Assert.That(result, Is.EqualTo(0));
    }

    [Test]
    public void Compare_WhenFirstRequirementHasLowerWeight_ReturnsNegativeOne()
    {
        var sorter = new RequirementWeightSorter();
        var requirement1 = new TestData.TestRequirement(true, 50);
        var requirement2 = new TestData.TestRequirement(true, 100);
        int result = sorter.Compare(requirement1, requirement2);

        Assert.That(result, Is.EqualTo(-1));
    }

    [Test]
    public void Compare_WhenFirstRequirementHasHigherWeight_ReturnsOne()
    {
        var sorter = new RequirementWeightSorter();
        var requirement1 = new TestData.TestRequirement(true, 100);
        var requirement2 = new TestData.TestRequirement(true, 50);
        int result = sorter.Compare(requirement1, requirement2);

        Assert.That(result, Is.EqualTo(1));
    }

    [Test]
    public void Compare_WhenRequirementsHaveSameWeight_ReturnsZero()
    {
        var sorter = new RequirementWeightSorter();
        var requirement1 = new TestData.TestRequirement(true, hash: [1, 2, 3]);
        var requirement2 = new TestData.TestRequirement(true, hash: [1, 2, 4]);
        int result = sorter.Compare(requirement1, requirement2);

        Assert.That(result, Is.EqualTo(0));
    }

    [TestCaseSource(typeof(TestData), nameof(TestData.CaseForEachRequirementType))]
    public void Compare(
        Requirement requirement1,
        Requirement requirement2,
        int expected)
    {
        var sorter = new RequirementWeightSorter();
        int result = sorter.Compare(requirement1, requirement2);

        switch (result)
        {
            case var _ when result < 0:
                Assert.That(result, Is.LessThanOrEqualTo(expected));
                break;
            case var _ when result > 0:
                Assert.That(result, Is.GreaterThanOrEqualTo(expected));
                break;
            default:
                Assert.That(result, Is.EqualTo(expected));
                break;
        }
    }
}

file class TestData
{
    private static int _counter = 0;
    public static Requirement GetNewRequirement() => new SampleRequirement(_counter++.ToString());
    public static Requirement[] GetNewRequirements(int count)
    {
        var requirements = new Requirement[count];
        for (var i = 0; i < count; i++) { requirements[i] = GetNewRequirement(); }
        return requirements;
    }

    public static IEnumerable CaseForEachRequirementType
    {
        get
        {
            yield return new TestCaseData(
                new RunAsAdminRequirement(),
                new RunAsAdminRequirement(),
                0
            ).SetCategory("Equal");

            yield return new TestCaseData(
                new RunAsAdminRequirement(),
                new UsingNamespace("System"),
                -1
            ).SetCategory("Hash Difference");

            yield return new TestCaseData(
                new UsingNamespace("System"),
                new RunAsAdminRequirement(),
                1
            ).SetCategory("Hash Difference");

            yield return new TestCaseData(
                new ModuleSpec("TestModule"),
                new PSEditionRequirement(PSEdition.Desktop),
                1
            ).SetCategory("Weight Difference");

            yield return new TestCaseData(
                new PSEditionRequirement(PSEdition.Desktop),
                new ModuleSpec("TestModule"),
                -1
            ).SetCategory("Weight Difference");

            yield return new TestCaseData(
                new ModuleSpec("TestModule"),
                new ModuleSpec("TestModule"),
                0
            ).SetCategory("Equal");

            yield return new TestCaseData(
                new ModuleSpec("TestModule-2"),
                new ModuleSpec("TestModule-1"),
                -1
            ).SetCategory("Hash Difference");

            yield return new TestCaseData(
                new ModuleSpec("TestModule-1"),
                new ModuleSpec("TestModule-2"),
                1
            ).SetCategory("Hash Difference");
        }
    }

    public static IEnumerable AddRequirementTests
    {
        get
        {
            yield return new TestCaseData(
                arg: GetNewRequirements(1)
            ).SetDescription("Single Requirement");

            yield return new TestCaseData(
                arg: GetNewRequirements(2)
            ).SetDescription("Two Requirements");

            yield return new TestCaseData(
                arg: GetNewRequirements(10)
            ).SetDescription("Multiple Requirements");
        }
    }

    internal sealed class TestRequirement : Requirement
    {
        public TestRequirement(
            bool supportsMultiple,
            uint weight = 50,
            byte[]? hash = null) : base()
        {
            SupportsMultiple = supportsMultiple;
            Weight = weight;
            Hash = hash ?? SHA1.HashData(Encoding.UTF8.GetBytes(weight.ToString()));
        }

        public override string GetInsertableLine(Hashtable data) => throw new NotImplementedException();
        public override bool IsCompatibleWith(Requirement other) => throw new NotImplementedException();
    }

    internal sealed class SampleRequirement : Requirement
    {
        private readonly string _data;
        public SampleRequirement(string data) : base()
        {
            _data = data;
            SupportsMultiple = true;
            Hash = SHA1.HashData(Encoding.UTF8.GetBytes(data));
        }

        public override bool IsCompatibleWith(Requirement other) => true;
        public override string GetInsertableLine(Hashtable _data) => string.Empty;
    }

    internal sealed class IncompatibleRequirement : Requirement
    {
        public IncompatibleRequirement() : base()
        {
            SupportsMultiple = false;
            Hash = SHA1.HashData(Encoding.UTF8.GetBytes("Incompatible"));
        }

        public override bool IsCompatibleWith(Requirement other) => false;
        public override string GetInsertableLine(Hashtable _data) => string.Empty;
    }
}
