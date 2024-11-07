// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Globalization;
using System.Text;
using Moq;

namespace Compiler.Test;

[TestFixture]
public class ProgramTests {
    [Test, Parallelizable]
    public void GetFilesToCompile(
        [Values(0, 1, 10, 100)] int numberOfFiles,
        [Values(0, 1, 10)] int nestedLevel,
        [Values(false, true)] bool includeSomeIgnoredFiles
    ) {
        var (rootPath, files) = TestData.GenerateTestFiles(numberOfFiles, nestedLevel, includeSomeIgnoredFiles);
        var result = Program.GetFilesToCompile(rootPath).Unwrap();

        Assert.That(result, Is.EquivalentTo(files));

        if (numberOfFiles == 0) {
            Assert.That(result, Is.Empty);
        }
    }

    [Test]
    public void GetFilesToCompile_ErrorOnNonExistingPath() {
        var path = TestUtils.GenerateUniqueDirectory(null, false);
        var result = Program.GetFilesToCompile(path);

        Assert.That(result.IsFail, Is.True);
        Assert.Multiple(() => {
            var exception = result.UnwrapError();
            Assert.That(exception.Message, Does.Contain(path));
            Assert.That(exception.Is<FileNotFoundException>(), Is.True);
        });
    }

    [Test]
    public void GetFilesToCompile_ErrorOnIncorrectFileType() {
        var path = TestUtils.GenerateUniqueFile(null, ".psm1", true);
        var result = Program.GetFilesToCompile(path);

        Assert.That(result.IsFail, Is.True);
        Assert.Multiple(() => {
            var exception = result.UnwrapError();
            Assert.That(exception.Message, Does.Contain(path));
            Assert.That(exception, Is.InstanceOf<InvalidInputError>());
        });
    }

    [Test, Parallelizable, Repeat(10)]
    public void EnsureDirectoryStructure(
        [Values(0, 1, 10, 100)] int numberOfFiles,
        [Values(0, 1, 10)] int nestedLevel
    ) {
        var (rootPath, files) = TestData.GenerateTestFiles(numberOfFiles, nestedLevel, false);
        var outputPath = TestUtils.GenerateUniqueDirectory();
        Program.EnsureDirectoryStructure(rootPath, outputPath, files);

        foreach (var file in files) {
            var expectedPath = file.Replace(rootPath, outputPath);
            Assert.That(Directory.Exists(Directory.GetParent(expectedPath)!.FullName), Is.True);
        }

        if (numberOfFiles == 0) {
            Assert.That(Directory.GetFiles(outputPath), Is.Empty);
        }
    }

    [Test]
    public void Output_ToFile(
        [Values(false, true)] bool overwrite,
        [Values("FooBar", null)] string? expectedContent = default
    ) {
        const string content = "Hello World";
        expectedContent ??= content;

        var sourceDirectory = TestUtils.GenerateUniqueDirectory();
        var outputDirectory = TestUtils.GenerateUniqueDirectory();
        var sourceFile = TestUtils.GenerateUniqueFile(sourceDirectory, ".ps1", true, content);

        var relativePath = Path.GetRelativePath(sourceDirectory, sourceFile);
        var outputPath = Path.Combine(outputDirectory, relativePath);

        // Mock the input stream to always return 'n' for overwrite.
        var inputStream = new Mock<TextReader>();
        inputStream.Setup(x => x.ReadLine()).Returns("n");
        Console.SetIn(inputStream.Object);

        Program.EnsureDirectoryStructure(sourceDirectory, outputDirectory, [sourceFile]);
        Program.Output(sourceDirectory, outputDirectory, sourceFile, content, overwrite);
        Program.Output(sourceDirectory, outputDirectory, sourceFile, expectedContent, overwrite);

        Assert.Multiple(() => {
            Assert.That(File.Exists(outputPath), Is.True);
            Assert.That(File.ReadAllText(outputPath), Is.EqualTo(overwrite ? expectedContent : content));
        });
    }

    [Test]
    public void Output_ToFileOverwrites() {
        const string content = "Hello World";
        var sourceDirectory = TestUtils.GenerateUniqueDirectory();
        var outputDirectory = TestUtils.GenerateUniqueDirectory();
        var sourceFile = TestUtils.GenerateUniqueFile(sourceDirectory, ".ps1", true, content);

        var relativePath = Path.GetRelativePath(sourceDirectory, sourceFile);
        var outputPath = Path.Combine(outputDirectory, relativePath);

        // Mock the input stream to always return 'y' for overwrite.
        var inputStream = new Mock<TextReader>();
        inputStream.Setup(x => x.ReadLine()).Returns("y");
        Console.SetIn(inputStream.Object);

        Program.EnsureDirectoryStructure(sourceDirectory, outputDirectory, [sourceFile]);
        Program.Output(sourceDirectory, outputDirectory, sourceFile, "FooBar", true);
        Program.Output(sourceDirectory, outputDirectory, sourceFile, content, false);

        Assert.Multiple(() => {
            Assert.That(File.Exists(outputPath), Is.True);
            Assert.That(File.ReadAllText(outputPath), Is.EqualTo(content));
        });
    }

    [Test]
    public void Output_ToConsole() {
        const string content = "Hello World";
        var sourceDirectory = TestUtils.GenerateUniqueDirectory();
        var sourceFile = TestUtils.GenerateUniqueFile(sourceDirectory, ".ps1", true);

        var writer = new StringWriter();
        Console.SetOut(writer);

        Program.Output(sourceDirectory, null, sourceFile, content, false);
        Assert.That(writer.ToString(), Is.EqualTo(content));
    }
}

file static class TestData {
    public static IEnumerable OutputData {
        get {
            var sourceDirectory = TestUtils.GenerateUniqueDirectory();
            var outputDirectory = TestUtils.GenerateUniqueDirectory();
            var sourceFile = TestUtils.GenerateUniqueFile(sourceDirectory, ".ps1", true);

            yield return new TestCaseData(sourceDirectory, null, sourceFile, false)
                .SetDescription("Output to console");

            yield return new TestCaseData(sourceDirectory, outputDirectory, sourceFile, false)
                .SetDescription("Output to file without overwrite");


            var outputFile = Path.Combine(outputDirectory, Path.GetRelativePath(sourceDirectory, sourceFile));
            File.WriteAllText(outputFile, "Foo Bar");

            yield return new TestCaseData(sourceDirectory, outputDirectory, sourceFile, false, "Foo Bar")
                .SetDescription("Output to file without overwrite");

            yield return new TestCaseData(sourceDirectory, outputDirectory, sourceFile, true)
                .SetDescription("Output to file with overwrite");
        }
    }

    public static ValueTuple<string, string[]> GenerateTestFiles(int numberofFiles, int nestedLevel, bool includeSomeIgnoredFiles) {
        var random = TestContext.CurrentContext.Random;
        var rootPath = TestUtils.GenerateUniqueDirectory();
        Directory.CreateDirectory(rootPath);

        var expectedFiles = new List<string>();
        var filesPerLevel = new Dictionary<int, int>();
        for (var i = 0; i < numberofFiles; i++) {
            var level = random.Next(0, nestedLevel + 1);
            if (filesPerLevel.TryGetValue(level, out var levelCount)) {
                filesPerLevel[level] = 0;
            }

            filesPerLevel[level] = levelCount + 1;
        }

        var lastLevel = rootPath;
        for (var i = 0; i < nestedLevel || (nestedLevel == 0 && i == 0); i++) {
            var levelPath = lastLevel = TestUtils.GenerateUniqueDirectory(lastLevel, true);

            if (!filesPerLevel.TryGetValue(i, out var filesAtLevel)) continue;
            for (var j = 0; j < filesAtLevel; j++) {
                var filePath = TestUtils.GenerateUniqueFile(levelPath, ".ps1", false);
                var text = new StringBuilder();

                // Always add an ignored if there aren't any incase there is only one file.
                if (includeSomeIgnoredFiles && random.Next(0, 2) == 0) {
                    text.AppendLine("#!ignore");
                } else {
                    expectedFiles.Add(filePath);
                }

                text.Append(CultureInfo.InvariantCulture, $"""Write-Host "Hello World from {filePath}""");
                File.WriteAllText(filePath, text.ToString());
            }
        }

        return (rootPath, expectedFiles.ToArray());
    }
}
