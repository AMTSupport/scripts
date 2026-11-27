using System;
using System.IO;

namespace AMT.PowerShell.Common.Module;

public class Flag {
    public Flag(string context) {
        if (string.IsNullOrWhiteSpace(context)) {
            throw new ArgumentException("Context is required.", nameof(context));
        }

        this.Context = context;
        this.FlagPath = FlagPathResolver.GetFlagPath(context);
    }

    public string Context { get; }

    public string FlagPath { get; }

    public virtual bool Exists() => File.Exists(this.FlagPath);

    public virtual object? GetData() {
        if (!this.Exists()) {
            return null;
        }

        var content = File.ReadAllText(this.FlagPath);
        if (string.IsNullOrEmpty(content)) {
            return null;
        }

        return content.TrimEnd('\r', '\n');
    }

    public virtual void Set(object? data) {
        EnsureFlagDirectory(this.FlagPath);

        if (data is null) {
            File.WriteAllText(this.FlagPath, string.Empty);
            return;
        }

        File.WriteAllText(this.FlagPath, data.ToString() ?? string.Empty);
    }

    public virtual void Remove() {
        if (!this.Exists()) {
            return;
        }

        File.Delete(this.FlagPath);
    }

    private static void EnsureFlagDirectory(string flagPath) {
        var directory = Path.GetDirectoryName(flagPath);
        if (!string.IsNullOrWhiteSpace(directory)) {
            Directory.CreateDirectory(directory);
        }
    }
}
