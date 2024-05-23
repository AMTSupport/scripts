using System.Collections;
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
