using System.IO;

namespace AMT.PowerShell.Common.Commands.Temp;

internal static class TempFolderOperations {
    internal static string GetNamed(string name, bool forceEmpty) {
        var folder = Path.Combine(Path.GetTempPath(), name);

        if (forceEmpty && Directory.Exists(folder)) {
            Directory.Delete(folder, recursive: true);
        }

        if (!Directory.Exists(folder)) {
            Directory.CreateDirectory(folder);
        }

        return folder;
    }

    internal static string GetUnique() => GetNamed(Path.GetRandomFileName(), forceEmpty: true);

    internal static void TryDelete(string path) {
        try {
            if (Directory.Exists(path)) {
                Directory.Delete(path, recursive: true);
            }
        } catch {
        }
    }
}
