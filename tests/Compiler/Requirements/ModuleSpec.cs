using Compiler.Module;
using Compiler.Requirements;
using Newtonsoft.Json;
using System.Collections;

namespace Compiler.Test.Requirements;

[TestFixture]
public class ModuleSpecTests
{
    [TestCaseSource(typeof(TestData), nameof(TestData.InsetableLinesCases))]
    public string GetInsertableLine_ReturnsCorrectLine(ModuleSpec moduleSpec)
    {
        return moduleSpec.GetInsertableLine();
    }

    [TestCaseSource(typeof(TestData), nameof(TestData.MatchTestCases))]
    public ModuleMatch CompareTo_ReturnsModuleMatchExact(
        ModuleSpec moduleSpec1,
        ModuleSpec moduleSpec2
    )
    {
        var moduleMatch = moduleSpec1.CompareTo(moduleSpec2);
        return moduleMatch;
    }
}

public class TestData
{
    public static IEnumerable InsetableLinesCases
    {
        get
        {
            var guid = Guid.NewGuid();

            yield return new TestCaseData(new ModuleSpec(
                "MyModule"
            )).Returns("#Requires -Modules @{ModuleName = 'MyModule';ModuleVersion = '0.0.0.0';}").SetName("Only name");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid
            )).Returns($$"""#Requires -Modules @{ModuleName = 'MyModule';GUID = {{guid}};ModuleVersion = '0.0.0.0';}""").SetName("Name and guid");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0")
            )).Returns($$"""#Requires -Modules @{ModuleName = 'MyModule';GUID = {{guid}};ModuleVersion = '1.0.0';}""").SetName("Name, guid and minimum version");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            )).Returns($$"""#Requires -Modules @{ModuleName = 'MyModule';GUID = {{guid}};ModuleVersion = '1.0.0';MaximumVersion = '2.0.0';}""").SetName("Name, guid, minimum and maximum version");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0"),
                new Version("1.5.0")
            )).Returns($$"""#Requires -Modules @{ModuleName = 'MyModule';GUID = {{guid}};ModuleVersion = '1.0.0';MaximumVersion = '2.0.0';RequiredVersion = '1.5.0';}""").SetName("All properties");
        }
    }

    public static IEnumerable MatchTestCases
    {
        get
        {
            var guid = Guid.NewGuid();

            #region Same matches
            yield return new TestCaseData(new ModuleSpec(
                "MyModule"
            ), new ModuleSpec(
                "MyModule"
            )).Returns(ModuleMatch.Same).SetName("Same match with name");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid
            ), new ModuleSpec(
                "MyModule",
                guid
            )).Returns(ModuleMatch.Same).SetName("Same match with guid");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0")
            )).Returns(ModuleMatch.Same).SetName("Same match with guid and minimum version");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            )).Returns(ModuleMatch.Same).SetName("Same match with guid, minimum and maximum version");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0"),
                new Version("1.5.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0"),
                new Version("1.5.0")
            )).Returns(ModuleMatch.Same).SetName("Same match with all properties");

            // TODO - handle this better?, maybe a specific enum for it.
            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                null,
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0")
            )).Returns(ModuleMatch.Same).SetName("Same match because both are technically stricter");
            #endregion

            #region Looser matches
            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.3.0"),
                new Version("1.9.0")
            )).Returns(ModuleMatch.Looser).SetName("Looser match from smaller version range");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                null,
                null,
                new Version("1.5.0")
            )).Returns(ModuleMatch.Looser).SetName("Looser match from required version");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid
            ), new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0")
            )).Returns(ModuleMatch.Looser).SetName("Looser match with minimum version because of missing minimum version");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid
            ), new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            )).Returns(ModuleMatch.Looser).SetName("Looser match with version range because of missing version range");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("1.8.0")
            )).Returns(ModuleMatch.Looser).SetName("Looser match with maximum version because of smaller version range");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.1.0"),
                new Version("2.0.0")
            )).Returns(ModuleMatch.Looser).SetName("Looser match with minimum version because of smaller version range");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0"),
                new Version("1.5.0")
            )).Returns(ModuleMatch.Looser).SetName("Looser match from bigger version range with new required version");
            #endregion

            #region Stricter matches
            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.3.0"),
                new Version("1.9.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            )).Returns(ModuleMatch.Stricter).SetName("Stricter match from bigger version range");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0"),
                new Version("1.5.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            )).Returns(ModuleMatch.Stricter).SetName("Stricter match from bigger version range with existing required version");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("1.8.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            )).Returns(ModuleMatch.Stricter).SetName("Stricter match with maximum version because of bigger version range");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.1.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            )).Returns(ModuleMatch.Stricter).SetName("Stricter match with minimum version because of bigger version range");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                guid
            )).Returns(ModuleMatch.Stricter).SetName("Stricter match with version range because of missing version range");
            #endregion

            #region Incompatible matches
            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                null,
                new Version("0.9.0")
            )).Returns(ModuleMatch.Incompatible).SetName("Incompatible match because of maximum version lower than minimum version");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                new Version("2.1.0"),
                new Version("2.5.0")
            )).Returns(ModuleMatch.Incompatible).SetName("Incompatible match because of minimum version higher than maximum version");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                null,
                null,
                new Version("2.5.0")
            )).Returns(ModuleMatch.Incompatible).SetName("Incompatible match because of required version higher than maximum version");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                null,
                null,
                new Version("0.5.0")
            )).Returns(ModuleMatch.Incompatible).SetName("Incompatible match because of required version lower than minimum version");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                RequiredVersion: new Version("1.0.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                RequiredVersion: new Version("1.0.1")
            )).Returns(ModuleMatch.Incompatible).SetName("Incompatible match because of different required version");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                null,
                null,
                new Version("2.5.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            )).Returns(ModuleMatch.Incompatible).SetName("Incompatible match because of required version higher than maximum version");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                guid,
                null,
                null,
                new Version("0.5.0")
            ), new ModuleSpec(
                "MyModule",
                guid,
                new Version("1.0.0")
            )).Returns(ModuleMatch.Incompatible).SetName("Incompatible match because of required version lower than minimum version");
            #endregion
        }
    }
}
