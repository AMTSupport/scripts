using System.Reflection;
using System.Runtime.CompilerServices;
using Compiler.Requirements;

namespace Compiler.Test;

public class TestUtils
{
    public static PathedModuleSpec GetModuleSpecFromContent(string content)
    {
        var tempFile = Path.GetTempFileName();
        File.WriteAllText(tempFile, content);
        return new PathedModuleSpec(tempFile);
    }

    private static string CallerFilePath([CallerFilePath] string? callerFilePath = null) =>
        callerFilePath ?? throw new ArgumentNullException(nameof(callerFilePath));

    public static string ProjectDirectory() => Path.GetDirectoryName(CallerFilePath())!;

    public static string RepositoryDirectory() => Path.GetDirectoryName(Path.Combine(ProjectDirectory(), "../../"))!;
}

