// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Runtime.CompilerServices;
using Compiler.Module.Resolvable;
using Compiler.Requirements;

namespace Compiler.Test;

public class TestUtils {
    public static PathedModuleSpec GetModuleSpecFromContent(string content) {
        var sourceRoot = TestContext.CurrentContext.WorkDirectory;
        var tempFile = Path.GetFullPath($"{sourceRoot}/{TestContext.CurrentContext.Random.GetString(6)}.ps1");

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

        var random = TestContext.CurrentContext.Random;
        var sourceRoot = Path.Combine(TestContext.CurrentContext.WorkDirectory, random.GetString(6));
        var testScripts = new string[numberOfScripts];

        if (createFiles) Directory.CreateDirectory(sourceRoot);

        for (var i = 0; i < numberOfScripts; i++) {
            var path = Path.GetFullPath($"{sourceRoot}/{random.GetString(6)}.ps1");
            if (createFiles) File.Create(path).Close();
            testScripts[i] = path;
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
}
