// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Globalization;
using Compiler.Requirements;

namespace Compiler.Test.Requirements;

[TestFixture]
public class RequirementGroupTests {
    [Test]
    public void Requirements_EmptyListByDefault() {
        var requirementGroup = new RequirementGroup();

        var requirements = requirementGroup.GetRequirements();
        Assert.That(requirements, Is.Empty);
    }

    [Test]
    public void Requriements_EmptyWhenNoneOfTypeAdded() {
        var requirementGroup = new RequirementGroup();
        requirementGroup.AddRequirement(new TestRequirement(true));

        var requirements = requirementGroup.GetRequirements<SampleRequirement>();
        Assert.That(requirements, Is.Empty);
    }

    [Test]
    public void RemoveRequirement_FalseWhenRequirementNotPresent() {
        var requirementGroup = new RequirementGroup();
        var requirement = new TestRequirement(true);

        var result = requirementGroup.RemoveRequirement(requirement);
        Assert.That(result, Is.False);
    }

    [TestCaseSource(typeof(TestData), nameof(TestData.AddRequirementTests))]
    public void AddRequirement(Requirement[] requirements) {
        var requirementGroup = new RequirementGroup();

        foreach (var requirement in requirements) {
            requirementGroup.AddRequirement(requirement);
        }

        var storedRequirements = requirementGroup.GetRequirements<Requirement>();
        Assert.Multiple(() => {
            Assert.That(storedRequirements, Has.Count.EqualTo(requirements.Length));
            Assert.That(storedRequirements, Is.EquivalentTo(requirements));
        });
    }

    [TestCaseSource(typeof(TestData), nameof(TestData.AddRequirementTests))]
    public void RemoveRequirement(Requirement[] requirements) {
        var requirementGroup = new RequirementGroup();

        foreach (var requirement in requirements) {
            requirementGroup.AddRequirement(requirement);
        }

        var removingCount = (int)Math.Ceiling(requirements.Length / 2.0); // Ensure we remove at least one
        var removed = 0;
        for (var i = 0; i < removingCount; i++) {
            if (requirementGroup.RemoveRequirement(requirements[i])) removed++;
        }

        var storedRequirements = requirementGroup.GetRequirements<Requirement>();
        Assert.Multiple(() => {
            Assert.That(removed, Is.EqualTo(removingCount));
            Assert.That(storedRequirements, Has.Count.EqualTo(requirements.Length - removed));
            Assert.That(storedRequirements, Is.EquivalentTo(requirements.Skip(removingCount)));
        });
    }

    [Test, Repeat(1000)]
    public void GetRequirements_ShouldReturnAllRequirementsInOrderOfHashWhenSameWeight() {
        var requirementGroup = new RequirementGroup();
        var requirementsList = new List<Requirement>();
        for (var i = 0; i < 100; i++) {
            var requirement = new SampleRequirement(i.ToString(CultureInfo.InvariantCulture));
            requirementsList.Add(requirement);
            requirementGroup.AddRequirement(requirement);
        }

        var requirements = requirementGroup.GetRequirements();
        Assert.Multiple(() => {
            Assert.That(requirements, Has.Count.EqualTo(100));
            Assert.That(requirements, Is.Ordered.By(nameof(Requirement.Weight)));
            for (var i = 0; i < 100; i++) {
                Assert.That(requirements.ElementAt(i), Is.EqualTo(requirementsList[i]));
            }
        });
    }
}

file sealed class TestData {
    private static int Counter;
    public static Requirement GetNewRequirement() => new SampleRequirement(Counter++.ToString(CultureInfo.InvariantCulture));
    public static Requirement[] GetNewRequirements(int count) {
        var requirements = new Requirement[count];
        for (var i = 0; i < count; i++) { requirements[i] = GetNewRequirement(); }
        return requirements;
    }

    public static IEnumerable AddRequirementTests {
        get {
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
}
