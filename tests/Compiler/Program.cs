// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Globalization;
using System.Text;

namespace Compiler.Test;

[TestFixture]
public class ProgramTests {
    [Test, Parallelizable]
    public void GetFilesToCompile(
        [Values(1, 10, 100)] int numberOfFiles,
        [Values(0, 1, 10)] int nestedLevel,
        [Values(false, true)] bool includeSomeIgnoredFiles
    ) {
        var (rootPath, files) = TestData.GenerateTestFiles(numberOfFiles, nestedLevel, includeSomeIgnoredFiles);
        var result = Program.GetFilesToCompile(rootPath).Unwrap();

        Assert.That(result, Is.EquivalentTo(files));
    }

    [Test, Parallelizable, Repeat(10)]
    public void EnsureDirectoryStructure(
        [Values(1, 10, 100)] int numberOfFiles,
        [Values(0, 1, 10)] int nestedLevel
    ) {
        var (rootPath, files) = TestData.GenerateTestFiles(numberOfFiles, nestedLevel, false);
        var outputPath = TestUtils.GenerateUniqueDirectory();
        Program.EnsureDirectoryStructure(rootPath, outputPath, files);

        foreach (var file in files) {
            var expectedPath = file.Replace(rootPath, outputPath);
            Assert.That(Directory.Exists(Directory.GetParent(expectedPath)!.FullName), Is.True);
        }
    }
}

file static class TestData {
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
