// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace AMT.PowerShell.Common.Commands.PackageManager;

internal static class PackageManagerOperations {
    private const string ChocolateyRelativePath = @"ProgramData\Chocolatey\bin\choco.exe";

    // Injectable seams for testing
    internal static Func<string?>? OsEnvironmentOverride { get; set; }
    internal static Func<string, string[], (int ExitCode, string Output)>? ProcessRunnerOverride { get; set; }
    internal static Func<string, bool>? ExecutableExistsOverride { get; set; }

    // Detect which package manager is available based on OS and executable presence.
    internal static PackageManagerKind DetectManager() {
        var os = OsEnvironmentOverride is not null
            ? OsEnvironmentOverride()
            : Environment.GetEnvironmentVariable("OS");

        if (os?.Equals("Windows_NT", StringComparison.OrdinalIgnoreCase) != true) {
            return PackageManagerKind.Unsupported;
        }

        // Verify the executable is present before claiming the manager is available.
        var exe = GetExecutable(PackageManagerKind.Chocolatey);
        var exists = ExecutableExistsOverride is not null
            ? ExecutableExistsOverride(exe)
            : File.Exists(exe);

        return exists ? PackageManagerKind.Chocolatey : PackageManagerKind.Unsupported;
    }

    // Build the executable path for the detected manager.
    internal static string GetExecutable(PackageManagerKind manager) => manager switch {
        PackageManagerKind.Chocolatey => BuildChocolateyPath(),
        _ => throw new NotSupportedException($"No executable for manager '{manager}'."),
    };

    // Run choco list --exact to test installation.
    // choco exits 0 whether or not the package is found, so we parse
    // the --limit-output lines (format: "name|version") to detect presence.
    internal static bool IsInstalled(PackageManagerKind manager, string packageName) {
        var (exitCode, output) = Run(
            GetExecutable(manager),
            new[] { "list", "--exact", "--limit-output", "--no-progress", packageName });

        if (exitCode != 0) {
            return false;
        }

        var prefix = packageName + "|";
        return output
            .Split(new[] { '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries)
            .Any(line => line.StartsWith(prefix, StringComparison.OrdinalIgnoreCase));
    }

    // Run choco install, appending checksum args when sha256 is supplied.
    internal static (int ExitCode, string Output) Install(PackageManagerKind manager, string packageName, string? sha256 = null) {
        var args = new List<string> { "install", "--confirm", "--limit-output", "--no-progress", "--exact", packageName };
        if (!string.IsNullOrEmpty(sha256)) {
            args.Add("--checksum");
            args.Add(sha256!);
            args.Add("--checksum-type");
            args.Add("sha256");
        }
        return Run(GetExecutable(manager), args.ToArray());
    }

    // Run choco uninstall.
    internal static (int ExitCode, string Output) Uninstall(PackageManagerKind manager, string packageName) =>
        Run(
            GetExecutable(manager),
            new[] { "uninstall", "--confirm", "--limit-output", "--no-progress", "--exact", packageName });

    // Run choco upgrade.
    internal static (int ExitCode, string Output) Update(PackageManagerKind manager, string packageName) =>
        Run(
            GetExecutable(manager),
            new[] { "upgrade", "--confirm", "--limit-output", "--no-progress", "--exact", packageName });

    // Construct an absolute path to choco.exe.
    // Path.Combine("C:", "ProgramData\...") produces drive-relative "C:ProgramData\..." on Windows.
    // Appending a backslash directly gives the absolute "C:\ProgramData\...".
    private static string BuildChocolateyPath() {
        var systemDrive = (Environment.GetEnvironmentVariable("SystemDrive") ?? "C:")
            .TrimEnd('\\', '/');
        return systemDrive + @"\" + ChocolateyRelativePath;
    }

    private static (int ExitCode, string Output) Run(string executable, string[] args) {
        if (ProcessRunnerOverride is not null) {
            return ProcessRunnerOverride(executable, args);
        }

        var psi = new ProcessStartInfo {
            FileName = executable,
            Arguments = string.Join(" ", args.Select(a => QuoteArg(a))),
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };

        using var process = Process.Start(psi)
            ?? throw new InvalidOperationException($"Failed to start '{executable}'.");

        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        process.WaitForExit();
        Task.WaitAll(stdoutTask, stderrTask);

        var output = string.Concat(stdoutTask.Result, Environment.NewLine, stderrTask.Result);
        return (process.ExitCode, output);
    }

    // Quote an argument that contains spaces.
    private static string QuoteArg(string arg) =>
        arg.IndexOf(' ') >= 0 ? $"\"{ arg }\"" : arg;
}
