// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using Compiler.Requirements;

namespace Compiler.Test.Requirements;

[TestFixture]
public class PSEditionTests {

    [Test, TestCaseSource(typeof(TestData), nameof(TestData.CaseForEachEdition))]
    public string GetInsertableStringFromEdition(PSEdition edition) {
        return new PSEditionRequirement(edition).GetInsertableLine([]);
    }

    [Test]
    public void AreIncompatableWithEachOther() {
        var desktop = new PSEditionRequirement(PSEdition.Desktop);
        var core = new PSEditionRequirement(PSEdition.Core);

        Assert.Multiple(() => {
            Assert.That(desktop.IsCompatibleWith(core), Is.False);
            Assert.That(core.IsCompatibleWith(desktop), Is.False);
        });
    }

    [Test, TestCaseSource(typeof(TestData), nameof(TestData.CaseForOtherRequirements))]
    public void IsCompatible_WithAnyOtherRequirementType(Requirement other) {
        var desktop = new PSEditionRequirement(PSEdition.Desktop);
        var core = new PSEditionRequirement(PSEdition.Core);

        Assert.Multiple(() => {
            Assert.That(desktop.IsCompatibleWith(other), Is.True);
            Assert.That(core.IsCompatibleWith(other), Is.True);
        });
    }

    public static class TestData {
        public static IEnumerable CaseForEachEdition {
            get {
                yield return new TestCaseData(PSEdition.Desktop).SetCategory("Desktop").Returns("#Requires -PSEdition Desktop");
                yield return new TestCaseData(PSEdition.Core).SetCategory("Core").Returns("#Requires -PSEdition Core");
            }
        }

        public static IEnumerable CaseForOtherRequirements {
            get {
                yield return new TestCaseData(new ModuleSpec("TestModule")).SetCategory("ModuleSpec");
                yield return new TestCaseData(new PSVersionRequirement(new Version(7, 0))).SetCategory("PSVersionRequirement");
                yield return new TestCaseData(new RunAsAdminRequirement()).SetCategory("RunAsAdminRequirement");
            }
        }
    }
}
