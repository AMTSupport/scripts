using System.Collections;
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
    [Test]
    public void AddRequirement_ShouldAddRequirementToList()
    {
        var requirementGroup = new RequirementGroup();
        var requirement = new SampleRequirement("Data");

        requirementGroup.AddRequirement(requirement);

        var storedRequirements = requirementGroup.GetRequirements<SampleRequirement>();
        Assert.Multiple(() =>
        {
            Assert.That(storedRequirements, Has.Count.EqualTo(1));
            Assert.That(storedRequirements, Does.Contain(requirement));
        });
    }

    [Test]
    public void RemoveRequirement_ShouldRemoveRequirementFromList()
    {
        var requirementGroup = new RequirementGroup();
        var requirement = new SampleRequirement("Data");
        requirementGroup.AddRequirement(requirement);

        var removed = requirementGroup.RemoveRequirement(requirement);

        var storedRequirements = requirementGroup.GetRequirements<SampleRequirement>();
        Assert.Multiple(() =>
        {
            Assert.That(removed, Is.True);
            Assert.That(storedRequirements, Is.Empty);
            Assert.That(storedRequirements, Does.Not.Contain(requirement));
        });
    }

    [Test]
    public void ReplaceRequirement_ShouldReplaceOldRequirementWithNewRequirement()
    {
        var requirementGroup = new RequirementGroup();
        var oldRequirement = new SampleRequirement("Data1");
        var newRequirement = new SampleRequirement("Data2");
        requirementGroup.AddRequirement(oldRequirement);

        var replaced = requirementGroup.ReplaceRequirement(oldRequirement, newRequirement);

        var storedRequirements = requirementGroup.GetRequirements<SampleRequirement>();
        Assert.Multiple(() =>
        {
            Assert.That(replaced, Is.True);
            Assert.That(storedRequirements, Has.Count.EqualTo(1));
            Assert.That(storedRequirements, Does.Not.Contain(oldRequirement));
            Assert.That(storedRequirements, Does.Contain(newRequirement));
        });
    }

    [Test, Repeat(100)]
    public void GetRequirements_ShouldReturnAllRequirementsInOrder()
    {
        var requirementGroup = new RequirementGroup();
        var requirement1 = new SampleRequirement("Data1");
        var requirement2 = new SampleRequirement("Data2");
        requirementGroup.AddRequirement(requirement1);
        requirementGroup.AddRequirement(requirement2);

        var requirements = requirementGroup.GetRequirements();

        Assert.Multiple(() =>
        {
            Assert.That(requirements, Has.Count.EqualTo(2));
            Assert.That(requirements.ElementAt(0), Is.EqualTo(requirement1));
            Assert.That(requirements.ElementAt(1), Is.EqualTo(requirement2));
        });

    }

    [Test]
    public void VerifyRequirements_ShouldReturnTrueWhenAllRequirementsAreCompatible()
    {
        var requirementGroup = new RequirementGroup();
        var requirement1 = new SampleRequirement("Data1");
        var requirement2 = new SampleRequirement("Data2");
        requirementGroup.AddRequirement(requirement1);
        requirementGroup.AddRequirement(requirement2);

        var result = requirementGroup.VerifyRequirements();
        Assert.That(result, Is.True);
    }

    [Test]
    public void VerifyRequirements_ShouldReturnFalseWhenIncompatibleRequirementsExist()
    {
        var requirementGroup = new RequirementGroup();
        var requirement1 = new SampleRequirement("Data1");
        var requirement2 = new IncompatibleRequirement();
        requirementGroup.AddRequirement(requirement1);
        requirementGroup.AddRequirement(requirement2);

        var result = requirementGroup.VerifyRequirements();
        Assert.That(result, Is.False);
    }

    private record SampleRequirement(string Data) : Requirement(true)
    {
        public override byte[] Hash => Encoding.UTF8.GetBytes(Data);
        public override bool IsCompatibleWith(Requirement other) => true;
        public override string GetInsertableLine() => string.Empty;
    }

    private record IncompatibleRequirement() : Requirement(true)
    {
        public override byte[] Hash => [];
        public override bool IsCompatibleWith(Requirement other) => false;
        public override string GetInsertableLine() => string.Empty;
    }
}
