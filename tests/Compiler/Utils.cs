// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Runtime.CompilerServices;
using Compiler.Requirements;

namespace Compiler.Test;

public class TestUtils {
    public static PathedModuleSpec GetModuleSpecFromContent(string content) {
        var tempFile = Path.GetTempFileName();
        File.WriteAllText(tempFile, content);
        return new PathedModuleSpec(tempFile);
    }

    private static string CallerFilePath([CallerFilePath] string? callerFilePath = null) =>
        callerFilePath ?? throw new ArgumentNullException(nameof(callerFilePath));

    public static string ProjectDirectory() => Path.GetDirectoryName(CallerFilePath())!;

    public static string RepositoryDirectory() => Path.GetDirectoryName(Path.Combine(ProjectDirectory(), "../../"))!;
}

