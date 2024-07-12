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
}

