using System;
using System.IO;

namespace AMT.PowerShell.Common.Module;

internal static class FlagPathResolver {
    private const string FlagFolderName = "Flags";

    public static string GetFlagPath(string context) {
        if (string.IsNullOrWhiteSpace(context)) {
            throw new ArgumentException("Context is required.", nameof(context));
        }

        var flagFolder = Path.Combine(Path.GetTempPath(), FlagFolderName);
        Directory.CreateDirectory(flagFolder);

        return Path.Combine(flagFolder, $"{context}.flag");
    }
}
