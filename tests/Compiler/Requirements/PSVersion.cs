using System.Collections;
using Compiler.Requirements;

namespace Compiler.Test.Requirements;

[TestFixture]
public class PSVersionTests
{

    [Test, TestCaseSource(typeof(TestData), nameof(TestData.CaseForVersionString))]
    public string GetInsertableLine_CheckContent(Version version)
    {
        var line = new PSVersionRequirement(version).GetInsertableLine([]);

        Assert.Multiple(() =>
        {
            Assert.That(line, Is.Not.Null);
            Assert.That(line, Is.Not.Empty);
            Assert.That(line, Does.StartWith("#Requires -Version"));
        });

        return line;
    }

    [TestCaseSource(typeof(TestData), nameof(TestData.CompatabilityCases))]
    public bool IsCompatible_WithOtherVersions(
        PSVersionRequirement current,
        PSVersionRequirement otherVersion
    )
    {
        Assert.Multiple(() =>
        {
            Assert.That(current, Is.Not.Null);
            Assert.That(otherVersion, Is.Not.Null);
        });

        return current.IsCompatibleWith(otherVersion);
    }

    public static class TestData
    {
        public static IEnumerable CaseForVersionString
        {
            get
            {
                yield return new TestCaseData(new Version(7, 0)).SetCategory("OnlyMajor").Returns("#Requires -Version 7");
                yield return new TestCaseData(new Version(7, 3)).SetCategory("MajorAndMinor").Returns("#Requires -Version 7.3");
                yield return new TestCaseData(new Version(7, 3, 1)).SetCategory("MajorMinorAndRevision").Returns("#Requires -Version 7.3.1");
            }
        }

        public static IEnumerable CompatabilityCases
        {
            get
            {
                yield return new TestCaseData(
                    new PSVersionRequirement(new Version(7, 0)),
                    new PSVersionRequirement(new Version(7, 0))
                ).SetName("Same version").Returns(true);

                yield return new TestCaseData(
                    new PSVersionRequirement(new Version(7, 0)),
                    new PSVersionRequirement(new Version(6, 0))
                ).SetName("If new version is below current, isn't compatable").Returns(false);

                yield return new TestCaseData(
                    new PSVersionRequirement(new Version(6, 0)),
                    new PSVersionRequirement(new Version(7, 0))
                ).SetName("If current version is below new, is compatable").Returns(true);

                yield return new TestCaseData(
                    new PSVersionRequirement(new Version(7, 0)),
                    new PSVersionRequirement(new Version(4, 0))
                ).SetName("If new version is below 4, isn't compatable").Returns(false);

                yield return new TestCaseData(
                    new PSVersionRequirement(new Version(4, 0)),
                    new PSVersionRequirement(new Version(7, 0))
                ).SetName("If current version is below 4, isn't compatable").Returns(false);

                yield return new TestCaseData(
                    new PSVersionRequirement(new Version(3, 0)),
                    new PSVersionRequirement(new Version(4, 0))
                ).SetName("If both versions are below 4, is compatable").Returns(true);

                yield return new TestCaseData(
                    new PSVersionRequirement(new Version(4, 0)),
                    new PSVersionRequirement(new Version(4, 0))
                ).SetName("If both versions are 4, is compatable").Returns(true);
            }
        }
    }
}
