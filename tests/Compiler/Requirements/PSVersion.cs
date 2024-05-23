using System.Collections;
using Compiler.Requirements;

namespace Compiler.Test.Requirements;

[TestFixture]
public class PSVersionTests
{

    [Test, TestCaseSource(typeof(TestData), nameof(TestData.CaseForVersionString))]
    public string GetInsertableLine_CheckContent(Version version)
    {
        var line = new PSVersionRequirement(version).GetInsertableLine();

        Assert.Multiple(() =>
        {
            Assert.That(line, Is.Not.Null);
            Assert.That(line, Is.Not.Empty);
            Assert.That(line, Does.StartWith("#Requires -PSEdition"));
        });

        return line;
    }

    [Test]
    public void IsCompatible_WithOtherVersions()
    {
        var desktop = new PSEditionRequirement(PSEdition.Desktop);
        var core = new PSEditionRequirement(PSEdition.Core);

        Assert.Multiple(() =>
        {
            Assert.That(desktop.IsCompatibleWith(core), Is.False);
            Assert.That(core.IsCompatibleWith(desktop), Is.False);
        });
    }

    [Test, TestCaseSource(typeof(TestData), nameof(TestData.CaseForOtherRequirements))]
    public void IsCompatible_WithAnyOtherRequirementType(Requirement other)
    {
        var desktop = new PSEditionRequirement(PSEdition.Desktop);
        var core = new PSEditionRequirement(PSEdition.Core);

        Assert.Multiple(() =>
        {
            Assert.That(desktop.IsCompatibleWith(other), Is.True);
            Assert.That(core.IsCompatibleWith(other), Is.True);
        });
    }

    public static class TestData
    {
        public static IEnumerable CaseForVersionString
        {
            get
            {
                yield return new TestCaseData(new Version(7, 0)).SetCategory("OnlyMajor").Returns("#Requires -PSEdition 7");
                yield return new TestCaseData(new Version(7, 3)).SetCategory("MajorAndMinor").Returns("#Requires -PSEdition 7.3");
                yield return new TestCaseData(new Version(7, 3, 1)).SetCategory("MajorMinorAndRevision").Returns("#Requires -PSEdition 7.3.1");
            }
        }

        public static IEnumerable CaseForOtherRequirements
        {
            get
            {
                yield return new TestCaseData(new ModuleSpec("TestModule")).SetCategory("ModuleSpec");
                yield return new TestCaseData(new PSVersionRequirement(new Version(7, 0))).SetCategory("PSVersionRequirement");
                yield return new TestCaseData(new RunAsAdminRequirement()).SetCategory("RunAsAdminRequirement");
            }
        }
    }
}
