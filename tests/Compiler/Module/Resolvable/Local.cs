// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using Compiler.Module;
using Compiler.Module.Resolvable;
using Compiler.Requirements;
using LanguageExt.Common;

namespace Compiler.Test.Module.Resolvable;

[TestFixture]
public class LocalModuleTests {
    [TestCaseSource(typeof(TestData), nameof(TestData.Constructor_ThrowingData))]
    public void Constructor_Throws(
        string parentPath,
        string filePath
    ) {
        var moduleSpec = new ModuleSpec(filePath);
        var exception = Assert.Catch<WrappedErrorExceptionalException>(() => new ResolvableLocalModule(parentPath, moduleSpec));
        Assert.That(exception.ToError(), Is.InstanceOf<InvalidModulePathError>());
    }

    [TestCaseSource(typeof(TestData), nameof(TestData.Constructor_ReturnsData))]
    public void Constructor_Returns(
        string parentPath,
        string filePath
    ) {
        var actualFileLocation = Path.GetFullPath(Path.Combine(parentPath, filePath));
        Directory.CreateDirectory(parentPath);
        File.Create(actualFileLocation).Close();

        var moduleSpec = new ModuleSpec(actualFileLocation);
        var module = new ResolvableLocalModule(parentPath, moduleSpec);

        Assert.Multiple(() => {
            Assert.That(module, Is.Not.Null);
            Assert.That(module, Is.InstanceOf<ResolvableLocalModule>());
            Assert.That(module.ModuleSpec.FullPath, Is.EqualTo(actualFileLocation));
        });

        File.Delete(actualFileLocation);
    }

    [Repeat(10), Parallelizable]
    [TestCaseSource(typeof(TestData), nameof(TestData.GetModuleMatch_MatchesByOnlyName))]
    public ModuleMatch GetModuleMatch_MatchesByOnlyName(
        string sourceRoot,
        string moduleOne,
        string moduleTwo
    ) {
        if (TestContext.CurrentContext.CurrentRepeatCount % 2 == 0) {
            (moduleTwo, moduleOne) = (moduleOne, moduleTwo);
        }

        var moduleSpecOne = new PathedModuleSpec(sourceRoot, moduleOne);
        var moduleSpecTwo = new PathedModuleSpec(sourceRoot, moduleTwo);
        var module = new ResolvableLocalModule(moduleSpecOne);

        return module.GetModuleMatchFor(moduleSpecTwo);
    }

    [TestCaseSource(typeof(TestData), nameof(TestData.Equals_Data))]
    public bool Equals(
        ResolvableLocalModule moduleOne,
        ResolvableLocalModule? moduleTwo
    ) {
        Assert.Multiple(() => {
            Assert.That(moduleOne, Is.Not.Null);
            if (moduleTwo != null) {
                Assert.That(moduleOne.Equals(moduleTwo), Is.EqualTo(moduleTwo?.Equals(moduleOne)));
            }
        });

        return moduleOne.Equals(moduleTwo);
    }

    [Test, Repeat(10), Parallelizable]
    public void GetHashCode_NeverDiffersFromModuleSpec() {
        var (module, _) = TestUtils.GetRandomModules(true);

        Assert.That(module.GetHashCode(), Is.EqualTo(module.ModuleSpec.GetHashCode()));
    }
}

file static class TestData {
    private static readonly string TestPath = Path.Combine(TestContext.CurrentContext.WorkDirectory, "LocalModuleTestData");
    private static readonly string TestParent = Path.Combine(TestPath, "Parent.ps1");
    private static readonly string TestChild = ".\\Child.psm1";

    public static IEnumerable Constructor_ThrowingData {
        get {
            yield return new TestCaseData("../Folder/Script.ps1", TestChild)
                .SetName("ParentPathIsNotAnAbsolutePath")
                .SetDescription("Throws an InvalidModulePathError when the parent path is not an absolute path.");

            yield return new TestCaseData(TestParent, TestChild)
                .SetName("ParentPathIsNotADirectory")
                .SetDescription("Throws an InvalidModulePathError when the parent path is not a directory.");

            yield return new TestCaseData(Path.Join(TestPath, "Secondary"), TestChild)
                .SetName("PathDoesNotExist")
                .SetDescription("Throws an InvalidModulePathError when the path does not exist.");

            yield return new TestCaseData(TestPath, TestChild)
                .SetName("PathNotAFile")
                .SetDescription("Throws an InvalidModulePathError when the path is not a file.");
        }
    }

    public static IEnumerable Constructor_ReturnsData {
        get {
            yield return new TestCaseData(TestPath, TestChild)
                .SetName("PathIsAFile")
                .SetDescription("Returns a ResolvableLocalModule when the path is a file.");
        }
    }

    public static IEnumerable GetModuleMatch_MatchesByOnlyName {
        get {
            var (sourceRoot, (childOne, childTwo)) = TestUtils.GenerateTestSources(true);

            yield return new TestCaseData(sourceRoot, childOne, childTwo)
                .Returns(ModuleMatch.None)
                .SetName("NoMatch")
                .SetDescription("Returns ModuleMatch.None when there is not a name match");

            yield return new TestCaseData(sourceRoot, childOne, childOne)
                .Returns(ModuleMatch.Same)
                .SetName("NameMatch")
                .SetDescription("Returns ModuleMatch.Same when there is a name match");
        }
    }

    public static IEnumerable Equals_Data {
        get {
            var (moduleOne, moduleTwo) = TestUtils.GetRandomModules(true);

            yield return new TestCaseData(moduleOne, moduleTwo)
                .Returns(false)
                .SetName("DifferentModuleSpec")
                .SetDescription("Returns false when the module specs are different.");

            yield return new TestCaseData(moduleOne, moduleOne)
                .Returns(true)
                .SetName("SameModuleSpec")
                .SetDescription("Returns true when the module specs are the same reference.");

            yield return new TestCaseData(moduleOne, null)
                .Returns(false)
                .SetName("NullModuleSpec")
                .SetDescription("Returns false when the module spec is null.");
        }
    }
}
