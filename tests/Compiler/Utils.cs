// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Runtime.CompilerServices;
using Compiler.Module.Resolvable;
using Compiler.Requirements;

namespace Compiler.Test;

public class TestUtils {
    public static PathedModuleSpec GetModuleSpecFromContent(string content) {
        var sourceRoot = GenerateUniqueDirectory();
        var tempFile = GenerateUniqueFile(sourceRoot, ".ps1");

        File.WriteAllText(tempFile, content);
        return new PathedModuleSpec(sourceRoot, tempFile);
    }

    private static string CallerFilePath([CallerFilePath] string? callerFilePath = null) =>
        callerFilePath ?? throw new ArgumentNullException(nameof(callerFilePath));

    public static string ProjectDirectory() => Path.GetDirectoryName(CallerFilePath())!;

    public static string RepositoryDirectory() => Path.GetDirectoryName(Path.Combine(ProjectDirectory(), "../../"))!;

    /// <summary>
    /// Generate test sources inside the current test context directory.
    /// </summary>
    /// <returns>
    /// A tuple containing the source root directory, and a tuple containing the paths of the generated scripts.
    /// </returns>
    public static (string, Tuple<string, string>) GenerateTestSources(bool createFiles = true) {
        const int numberOfScripts = 2;

        var sourceRoot = GenerateUniqueDirectory();
        var testScripts = new string[numberOfScripts];

        if (createFiles) Directory.CreateDirectory(sourceRoot);

        for (var i = 0; i < numberOfScripts; i++) {
            testScripts[i] = GenerateUniqueFile(sourceRoot, ".ps1", createFiles);
        }

        return (sourceRoot, new(testScripts[0], testScripts[1]));
    }


    public static (ResolvableLocalModule, ResolvableLocalModule) GetRandomModules(bool createFiles) {
        var (sourceRoot, (childOne, childTwo)) = GenerateTestSources(createFiles);

        var moduleSpecOne = new PathedModuleSpec(sourceRoot, childOne);
        var moduleOne = new ResolvableLocalModule(moduleSpecOne);

        var moduleSpecTwo = new PathedModuleSpec(sourceRoot, childTwo);
        var moduleTwo = new ResolvableLocalModule(moduleSpecTwo);

        return (moduleOne, moduleTwo);
    }

    /// <summary>
    /// Generate a unique directory inside the supplied parent.
    /// </summary>
    /// <param name="parent">The parent directory to create the unique directory inside, or the current test context directory if null</param>
    /// <returns>The path of the generated directory.</returns>
    /// <remarks>
    /// The directory is created and added to the cleanup list to be deleted after the test run.
    /// </remarks>
    public static string GenerateUniqueDirectory(string? parent = null, bool createDirectory = true) {
        var random = TestContext.CurrentContext.Random;
        var root = parent ?? TestContext.CurrentContext.WorkDirectory;
        string uniqueDirectory;
        do {
            uniqueDirectory = Path.Combine(root, random.GetString(6));
        } while (Directory.Exists(uniqueDirectory));

        if (createDirectory) Directory.CreateDirectory(uniqueDirectory);
        GlobalSetup.RequiresCleanup.Add(uniqueDirectory);

        return uniqueDirectory;
    }

    /// <summary>
    /// Generate a unique file inside the supplied parent.
    /// </summary>
    /// <param name="parent">The parent directory to create the unique file inside, or the current test context directory if null</param>
    /// <returns>The path of the generated file.</returns>
    public static string GenerateUniqueFile(string? parent = null, string extension = ".ps1", bool createFile = true, string? content = default) {
        var random = TestContext.CurrentContext.Random;
        var root = parent ?? GenerateUniqueDirectory();
        string uniqueFile;
        do {
            uniqueFile = Path.Combine(root, $"{random.GetString(6)}{extension}");
        } while (File.Exists(uniqueFile));

        if (createFile) {
            if (content is not null) {
                File.WriteAllText(uniqueFile, content);
            } else {
                File.Create(uniqueFile).Close();
            }
        }

        return uniqueFile;
    }
}
