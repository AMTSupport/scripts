// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using Compiler.Module;
using Compiler.Requirements;
using System.Collections;

namespace Compiler.Test.Requirements;

[TestFixture]
public class ModuleSpecTests {
    [TestCaseSource(typeof(TestData), nameof(TestData.InsetableLinesCases))]
    public string GetInsertableLine_ReturnsCorrectLine(ModuleSpec moduleSpec) => moduleSpec.GetInsertableLine([]);

    [TestCaseSource(typeof(TestData), nameof(TestData.MatchTestCases))]
    public ModuleMatch CompareTo(
        ModuleSpec moduleSpec1,
        ModuleSpec moduleSpec2
    ) {
        var moduleMatch = moduleSpec1.CompareTo(moduleSpec2);
        return moduleMatch;
    }

    [TestCaseSource(typeof(TestData), nameof(TestData.MergeSpecCases))]
    public ModuleSpec MergeSpec(
        ModuleSpec baseModuleSpec,
        ModuleSpec[] otherModuleSpecs
    ) {
        var mergedSpec = baseModuleSpec.MergeSpecs(otherModuleSpecs);

        Assert.Multiple(() => {
            Assert.That(mergedSpec.IsCompatibleWith(baseModuleSpec), Is.True);
            otherModuleSpecs.ToList().ForEach(otherModuleSpecs => Assert.That(mergedSpec.IsCompatibleWith(otherModuleSpecs), Is.True));
        });

        return mergedSpec;
    }
}

[TestFixture]
public class PathedModuleSpecTests {
    [TestCaseSource(typeof(TestData), nameof(TestData.MatchTestCases))]
    [TestCaseSource(typeof(TestData), nameof(TestData.ComparePathedSpecCases))]
    public ModuleMatch CompareTo(
        ModuleSpec moduleSpec1,
        ModuleSpec moduleSpec2
    ) => moduleSpec1.CompareTo(moduleSpec2);
}

file sealed class TestData {
    public static Guid Guid = Guid.Parse("d1b3b3b3-3b3b-3b3b-3b3b-3b3b3b3b3b3b");

    public static IEnumerable InsetableLinesCases {
        get {
            yield return new TestCaseData(new ModuleSpec(
                "MyModule"
            )).Returns("Using module 'MyModule'");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid
            )).Returns($$"""Using module @{ModuleName = 'MyModule';GUID = {{Guid}};}""");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            )).Returns($$"""Using module @{ModuleName = 'MyModule';GUID = {{Guid}};ModuleVersion = '1.0.0';}""");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                maximumVersion: new Version("2.0.0")
            )).Returns($$"""Using module @{ModuleName = 'MyModule';GUID = {{Guid}};MaximumVersion = '2.0.0';}""");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            )).Returns($$"""Using module @{ModuleName = 'MyModule';GUID = {{Guid}};ModuleVersion = '1.0.0';MaximumVersion = '2.0.0';}""");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0"),
                new Version("1.5.0")
            )).Returns($$"""Using module @{ModuleName = 'MyModule';GUID = {{Guid}};RequiredVersion = '1.5.0';}""");
        }
    }
    public static IEnumerable MatchTestCases {
        get {
            #region Same matches
            yield return new TestCaseData(new ModuleSpec(
                "MyModule"
            ), new ModuleSpec(
                "MyModule"
            )).Returns(ModuleMatch.Same);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid
            ), new ModuleSpec(
                "MyModule",
                Guid
            )).Returns(ModuleMatch.Same);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            )).Returns(ModuleMatch.Same);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            )).Returns(ModuleMatch.Same);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0"),
                new Version("1.5.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0"),
                new Version("1.5.0")
            )).Returns(ModuleMatch.Same);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                null,
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            )).Returns(ModuleMatch.MergeRequired);
            #endregion

            #region Looser matches
            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.3.0"),
                new Version("1.9.0")
            )).Returns(ModuleMatch.Looser);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                null,
                null,
                new Version("1.5.0")
            )).Returns(ModuleMatch.Looser);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            )).Returns(ModuleMatch.Looser);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            )).Returns(ModuleMatch.Looser);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("1.8.0")
            )).Returns(ModuleMatch.Looser);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.1.0"),
                new Version("2.0.0")
            )).Returns(ModuleMatch.Looser);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0"),
                new Version("1.5.0")
            )).Returns(ModuleMatch.Looser);
            #endregion

            #region Stricter matches
            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.3.0"),
                new Version("1.9.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            )).Returns(ModuleMatch.Stricter);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0"),
                new Version("1.5.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            )).Returns(ModuleMatch.Stricter);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("1.8.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            )).Returns(ModuleMatch.Stricter);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.1.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            )).Returns(ModuleMatch.Stricter);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid
            )).Returns(ModuleMatch.Stricter);
            #endregion

            #region Incompatible matches
            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                null,
                new Version("0.9.0")
            )).Returns(ModuleMatch.Incompatible);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("2.1.0"),
                new Version("2.5.0")
            )).Returns(ModuleMatch.Incompatible);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                null,
                null,
                new Version("2.5.0")
            )).Returns(ModuleMatch.Incompatible);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                null,
                null,
                new Version("0.5.0")
            )).Returns(ModuleMatch.Incompatible);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                requiredVersion: new Version("1.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                requiredVersion: new Version("1.0.1")
            )).Returns(ModuleMatch.Incompatible);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                null,
                null,
                new Version("2.5.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            )).Returns(ModuleMatch.Incompatible);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                null,
                null,
                new Version("0.5.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            )).Returns(ModuleMatch.Incompatible);
            #endregion
        }
    }
    public static IEnumerable MergeSpecCases {
        get {
            yield return new TestCaseData(new ModuleSpec(
                "MyModule"
            ), Array.Empty<ModuleSpec>()).Returns(new ModuleSpec(
                "MyModule"
            ));

            yield return new TestCaseData(new ModuleSpec(
                "MyModule"
            ), new ModuleSpec[] {
                new(
                    "MyModule",
                    Guid
                )
            }).Returns(new ModuleSpec(
                "MyModule",
                Guid
            ));

            yield return new TestCaseData(new ModuleSpec(
                "MyModule"
            ), new ModuleSpec[] {
                new(
                    "MyModule",
                    Guid,
                    new Version("1.0.0")
                )
            }).Returns(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            ));

            yield return new TestCaseData(new ModuleSpec(
                "MyModule"
            ), new ModuleSpec[] {
                new(
                    "MyModule",
                    Guid,
                    new Version("1.0.0"),
                    new Version("2.0.0")
                )
            }).Returns(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ));

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid
            ), new ModuleSpec[] {
                new(
                    "MyModule",
                    Guid,
                    new Version("1.0.0"),
                    new Version("2.0.0")
                )
            }).Returns(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ));

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec[] {
                new(
                    "MyModule",
                    Guid,
                    requiredVersion: new Version("1.5.0")
                )
            }).Returns(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0"),
                new Version("1.5.0")
            ));

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec[] {
                new(
                    "MyModule",
                    Guid,
                    new Version("1.5.0")
                )
            }).Returns(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.5.0"),
                new Version("2.0.0")
            ));

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec[] {
                new(
                    "MyModule",
                    Guid,
                    maximumVersion: new Version("1.5.0")
                )
            }).Returns(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("1.5.0")
            ));

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec[] {
                new(
                    "MyModule",
                    Guid,
                    new Version("1.5.0"),
                    new Version("1.8.0")
                )
            }).Returns(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.5.0"),
                new Version("1.8.0")
            ));
        }
    }
    public static IEnumerable ComparePathedSpecCases {
        get {
            var (sourceRoot, (testScript1, testScript2)) = TestUtils.GenerateTestSources();

            yield return new TestCaseData(
                new PathedModuleSpec(sourceRoot, testScript1),
                new PathedModuleSpec(sourceRoot, testScript1)
            ).Returns(ModuleMatch.Same);

            yield return new TestCaseData(
                new PathedModuleSpec(sourceRoot, testScript1),
                new PathedModuleSpec(sourceRoot, testScript2)
            ).Returns(ModuleMatch.None);

            yield return new TestCaseData(
                new PathedModuleSpec(sourceRoot, testScript1),
                new ModuleSpec("./test.ps1")
            ).Returns(ModuleMatch.None);

            yield return new TestCaseData(
                new PathedModuleSpec(sourceRoot, testScript1),
                new ModuleSpec("./test2.ps1")
            ).Returns(ModuleMatch.None);
        }
    }
}
