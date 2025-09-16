// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using Compiler.Module;
using Compiler.Requirements;
using System.Collections;

namespace Compiler.Test.Requirements;

[TestFixture]
public class ModuleSpecTests {
    [TestCaseSource(typeof(TestData), nameof(TestData.InsetableLinesCases))]
    public string GetInsertableLine(ModuleSpec moduleSpec) => moduleSpec.GetInsertableLine([]);

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

            if (otherModuleSpecs.Length == 0) {
                Assert.That(mergedSpec, Is.EqualTo(baseModuleSpec));
            } else {
                Assert.That(mergedSpec.CompareTo(baseModuleSpec), Is.EqualTo(ModuleMatch.Contained));
                Assert.That(baseModuleSpec.CompareTo(mergedSpec), Is.EqualTo(ModuleMatch.OtherContained));
                otherModuleSpecs.ToList().ForEach(otherModuleSpec => {
                    Assert.That(mergedSpec.IsCompatibleWith(otherModuleSpec), Is.True);
                    if (mergedSpec != otherModuleSpec) {
                        Assert.That(mergedSpec.Consumed, Does.Contain(otherModuleSpec));
                    } else {
                        Assert.That(mergedSpec.Consumed, Does.Not.Contain(otherModuleSpec));
                    }
                });
            }
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
    public static Guid Guid = TestContext.CurrentContext.Random.NextGuid();

    public static IEnumerable InsetableLinesCases {
        get {
            yield return new TestCaseData(new ModuleSpec(
                "MyModule"
            ))
            .SetArgDisplayNames("Name")
            .Returns("Using module 'MyModule'");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid
            ))
            .SetArgDisplayNames("Name", "GUID")
            .Returns($$"""Using module @{ModuleName = 'MyModule';GUID = {{Guid}};}""");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            ))
            .SetArgDisplayNames("Name", "GUID", "ModuleVersion")
            .Returns($$"""Using module @{ModuleName = 'MyModule';GUID = {{Guid}};ModuleVersion = '1.0.0';}""");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                maximumVersion: new Version("2.0.0")
            ))
            .SetArgDisplayNames("Name", "GUID", "MaximumVersion")
            .Returns($$"""Using module @{ModuleName = 'MyModule';GUID = {{Guid}};MaximumVersion = '2.0.0';}""");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ))
            .SetArgDisplayNames("Name", "GUID", "ModuleVersion", "MaximumVersion")
            .Returns($$"""Using module @{ModuleName = 'MyModule';GUID = {{Guid}};ModuleVersion = '1.0.0';MaximumVersion = '2.0.0';}""");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0"),
                new Version("1.5.0")
            ))
            .SetArgDisplayNames("Name", "GUID", "ModuleVersion", "MaximumVersion", "RequiredVersion")
            .Returns($$"""Using module @{ModuleName = 'MyModule';GUID = {{Guid}};RequiredVersion = '1.5.0';}""");

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                requiredVersion: new Version("1.5.0")
            ))
            .SetArgDisplayNames("Name", "GUID", "RequiredVersion")
            .Returns($$"""Using module @{ModuleName = 'MyModule';GUID = {{Guid}};RequiredVersion = '1.5.0';}""");
        }
    }
    public static IEnumerable MatchTestCases {
        get {
            #region Same matches
            yield return new TestCaseData(new ModuleSpec(
                "MyModule"
            ), new ModuleSpec(
                "MyModule"
            ))
            .SetArgDisplayNames("Same", "Name", "Name")
            .Returns(ModuleMatch.Same);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid
            ), new ModuleSpec(
                "MyModule",
                Guid
            ))
            .SetArgDisplayNames("Same", "Name, GUID", "Name, GUID")
            .Returns(ModuleMatch.Same);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            ))
            .SetArgDisplayNames("Same", "Name, GUID, ModuleVersion", "Name, GUID, ModuleVersion")
            .Returns(ModuleMatch.Same);

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
            ))
            .SetArgDisplayNames("Same", "Name, GUID, ModuleVersion, MaximumVersion", "Name, GUID, ModuleVersion, MaximumVersion")
            .Returns(ModuleMatch.Same);

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
            ))
            .SetArgDisplayNames("Same", "Name, GUID, ModuleVersion, MaximumVersion, RequiredVersion", "Name, GUID, ModuleVersion, MaximumVersion, RequiredVersion")
            .Returns(ModuleMatch.Same);
            #endregion

            #region MergeRequired matches
            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                maximumVersion: new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            ))
            .SetArgDisplayNames("MergeRequired", "Name, GUID, MaximumVersion", "Name, GUID, ModuleVersion")
            .Returns(ModuleMatch.MergeRequired);
            #endregion

            #region Looser matches
            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.3.0")
            ))
            .SetArgDisplayNames("Looser ModuleVersion", "Name, GUID, ModuleVersion", "Name, GUID, ModuleVersion")
            .Returns(ModuleMatch.Looser);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                maximumVersion: new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                maximumVersion: new Version("1.9.0")
            ))
            .SetArgDisplayNames("Looser MaximumVersion", "Name, GUID, MaximumVersion", "Name, GUID, MaximumVersion")
            .Returns(ModuleMatch.Looser);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                requiredVersion: new Version("1.5.0")
            ))
            .SetArgDisplayNames("Looser no RequiredVersion", "Name, GUID, ModuleVersion, MaximumVersion", "Name, GUID, RequiredVersion")
            .Returns(ModuleMatch.Looser);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            ))
            .SetArgDisplayNames("Looser no ModuleVersion", "Name, GUID", "Name, GUID, ModuleVersion")
            .Returns(ModuleMatch.Looser);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ))
            .SetArgDisplayNames("Looser no ModuleVersion or MaximumVersion", "Name, GUID", "Name, GUID, ModuleVersion, MaximumVersion")
            .Returns(ModuleMatch.Looser);
            #endregion

            #region Stricter matches
            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.3.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            ))
            .SetArgDisplayNames("Stricter ModuleVersion", "Name, GUID, ModuleVersion", "Name, GUID, ModuleVersion")
            .Returns(ModuleMatch.Stricter);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                maximumVersion: new Version("1.9.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                maximumVersion: new Version("2.0.0")
            ))
            .SetArgDisplayNames("Stricter MaximumVersion", "Name, GUID, MaximumVersion", "Name, GUID, MaximumVersion")
            .Returns(ModuleMatch.Stricter);


            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                requiredVersion: new Version("1.5.0")
            ), new ModuleSpec(
                "MyModule",
                Guid
            ))
            .SetArgDisplayNames("Stricter new RequiredVersion", "Name, GUID, RequiredVersion", "Name, GUID")
            .Returns(ModuleMatch.Stricter);
            #endregion

            #region Incompatible matches
            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                maximumVersion: new Version("0.9.0")
            ))
            .SetArgDisplayNames("Incompatible a.ModuleVersion > b.MaximumVersion", "Name, GUID, ModuleVersion", "Name, GUID, MaximumVersion")
            .Returns(ModuleMatch.Incompatible);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                maximumVersion: new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("2.1.0")
            ))
            .SetArgDisplayNames("Incompatible a.MaximumVersion < b.MinimumVersion", "Name, GUID, MaximumVersion", "Name, GUID, ModuleVersion")
            .Returns(ModuleMatch.Incompatible);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                requiredVersion: new Version("2.5.0")
            ))
            .SetArgDisplayNames("Incompatible b.RequiredVersion not within a.ModuleVersion..a.MaximumVersion", "Name, GUID, ModuleVersion, MaximumVersion", "Name, GUID, RequiredVersion")
            .Returns(ModuleMatch.Incompatible);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                requiredVersion: new Version("0.5.0")
            ))
            .SetArgDisplayNames("Incompatible a.ModuleVersion > b.RequiredVersion", "Name, GUID, ModuleVersion", "Name, GUID, RequiredVersion")
            .Returns(ModuleMatch.Incompatible);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                requiredVersion: new Version("1.0.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                requiredVersion: new Version("1.0.1")
            ))
            .SetArgDisplayNames("Incompatible a.RequiredVersion != b.RequiredVersion", "Name, GUID, RequiredVersion", "Name, GUID, RequiredVersion")
            .Returns(ModuleMatch.Incompatible);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                requiredVersion: new Version("2.5.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0"),
                new Version("2.0.0")
            ))
            .SetArgDisplayNames("Incompatible a.RequiredVersion !in b.ModuleVersion..b.MaximumVersion", "Name, GUID, RequiredVersion", "Name, GUID, ModuleVersion, MaximumVersion")
            .Returns(ModuleMatch.Incompatible);

            yield return new TestCaseData(new ModuleSpec(
                "MyModule",
                Guid,
                requiredVersion: new Version("0.5.0")
            ), new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.0.0")
            ))
            .SetArgDisplayNames("Incompatible a.RequiredVersion < b.ModuleVersion", "Name, GUID, RequiredVersion", "Name, GUID, ModuleVersion")
            .Returns(ModuleMatch.Incompatible);
            #endregion
        }
    }
    public static IEnumerable MergeSpecCases {
        get {
            var baseSpec = new ModuleSpec("MyModule");

            yield return new TestCaseData(baseSpec, Array.Empty<ModuleSpec>())
                .Returns(new ModuleSpec("MyModule"))
                .SetArgDisplayNames("No other specs");

            yield return new TestCaseData(baseSpec, new ModuleSpec[] {
                new(
                    "MyModule",
                    Guid
                )
            }).Returns(new ModuleSpec(
                "MyModule",
                Guid
            )).SetArgDisplayNames("Name", "Name, GUID");

            yield return new TestCaseData(baseSpec, new ModuleSpec[] {
                new(
                    "MyModule",
                    minimumVersion: new Version("1.0.0")
                )
            }).Returns(new ModuleSpec(
                "MyModule",
                minimumVersion: new Version("1.0.0")
            )).SetArgDisplayNames("Name", "Name, ModuleVersion");

            yield return new TestCaseData(baseSpec, new ModuleSpec[] {
                new(
                    "MyModule",
                    maximumVersion: new Version("2.0.0")
                )
            }).Returns(new ModuleSpec(
                "MyModule",
                maximumVersion: new Version("2.0.0")
            )).SetArgDisplayNames("Name", "Name, MaximumVersion");

            yield return new TestCaseData(baseSpec, new ModuleSpec[] {
                new(
                    "MyModule",
                    requiredVersion: new Version("1.5.0")
                )
            }).Returns(new ModuleSpec(
                "MyModule",
                requiredVersion: new Version("1.5.0")
            )).SetArgDisplayNames("Name", "Name, RequiredVersion");

            yield return new TestCaseData(baseSpec, new ModuleSpec[] {
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
            )).SetArgDisplayNames("Name", "Name, GUID, ModuleVersion, MaximumVersion");

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
            )).SetArgDisplayNames("Add RequiredVersion", "Name, GUID, ModuleVersion, MaximumVersion", "Name, GUID, RequiredVersion");

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
            )).SetArgDisplayNames("Increment ModuleVersion", "Name, GUID, ModuleVersion, MaximumVersion", "Name, GUID, ModuleVersion, MaximumVersion");

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
            )).SetArgDisplayNames("Decrease MaximumVersion", "Name, GUID, ModuleVersion, MaximumVersion", "Name, GUID, MaximumVersion");

            var specs = new ModuleSpec[] {
                new(
                    "MyModule",
                    Guid,
                    new Version("1.0.0"),
                    new Version("2.0.0")
                ),
                new(
                    "MyModule",
                    Guid,
                    new Version("1.5.0"),
                    new Version("1.8.0")
                )
            };
            yield return new TestCaseData(specs[0], specs[1..]).Returns(new ModuleSpec(
                "MyModule",
                Guid,
                new Version("1.5.0"),
                new Version("1.8.0"),
                null,
                specs
            )).SetArgDisplayNames("Multiple specs", "Name, GUID, ModuleVersion, MaximumVersion", "Name, GUID, ModuleVersion, MaximumVersion");
        }
    }
    public static IEnumerable ComparePathedSpecCases {
        get {
            var (sourceRoot, (testScript1, testScript2)) = TestUtils.GenerateTestSources();

            yield return new TestCaseData(
                new PathedModuleSpec(sourceRoot, testScript1),
                new PathedModuleSpec(sourceRoot, testScript1)
            )
            .SetArgDisplayNames("Same path")
            .Returns(ModuleMatch.Same);

            yield return new TestCaseData(
                new PathedModuleSpec(sourceRoot, testScript1),
                new PathedModuleSpec(sourceRoot, testScript2)
            )
            .SetArgDisplayNames("a.Path != b.Path")
            .Returns(ModuleMatch.None);

            yield return new TestCaseData(
                new PathedModuleSpec(sourceRoot, testScript1),
                new ModuleSpec("./test.ps1")
            )
            .SetArgDisplayNames("a.Path != b.Name")
            .Returns(ModuleMatch.None);
        }
    }
}
