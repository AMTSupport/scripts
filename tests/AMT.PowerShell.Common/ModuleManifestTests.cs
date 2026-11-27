// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Reflection;
using System.Text.RegularExpressions;

namespace AMT.PowerShell.Common.Tests;

[TestFixture]
public sealed class ModuleManifestTests {
    [Test]
    public void ManifestExportsEveryCmdletInTheAssembly() {
        var implemented = GetImplementedCmdlets();
        var exported = GetManifestEntries("CmdletsToExport");

        Assert.Multiple(() => {
            Assert.That(
                implemented.Except(exported, StringComparer.OrdinalIgnoreCase),
                Is.Empty,
                "Implementations missing from CmdletsToExport");
            Assert.That(
                exported.Except(implemented, StringComparer.OrdinalIgnoreCase),
                Is.Empty,
                "CmdletsToExport names without an implementation");
        });
    }

    [Test]
    public void EveryExportedCmdletHasDocumentationPage() {
        var documented = Directory
            .EnumerateFiles(Path.Combine(FindRepositoryRoot(), "docs", "docs", "module", "common"), "*.mdx", SearchOption.AllDirectories)
            .Select(Path.GetFileNameWithoutExtension)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        Assert.That(GetManifestEntries("CmdletsToExport").Except(documented, StringComparer.OrdinalIgnoreCase), Is.Empty);
    }

    [Test]
    public void ManifestExportsEveryCommandAlias() {
        var implemented = GetImplementedAliases();
        var exported = GetManifestEntries("AliasesToExport");

        Assert.That(
            implemented.Except(exported, StringComparer.OrdinalIgnoreCase),
            Is.Empty,
            "Aliases missing from AliasesToExport");
    }

    private static IReadOnlyCollection<string> GetImplementedCmdlets() =>
        typeof(AMT.PowerShell.Common.Commands.Assert.AssertEqualCommand).Assembly
            .GetTypes()
            .Select(type => type.GetCustomAttribute<CmdletAttribute>())
            .Where(attribute => attribute is not null)
            .Select(attribute => $"{attribute!.VerbName}-{attribute.NounName}")
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

    private static IReadOnlyCollection<string> GetImplementedAliases() =>
        typeof(AMT.PowerShell.Common.Commands.Assert.AssertEqualCommand).Assembly
            .GetTypes()
            .SelectMany(type => type.GetCustomAttributes<AliasAttribute>())
            .SelectMany(attribute => attribute.AliasNames)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

    private static IReadOnlyCollection<string> GetManifestEntries(string key) {
        var manifest = File.ReadAllText(FindManifestPath());
        var block = Regex.Match(
            manifest,
            key + @"\s*=\s*@\((?<body>.*?)\)",
            RegexOptions.Singleline);

        Assert.That(block.Success, Is.True, $"Could not find {key} in the module manifest.");

        return Regex.Matches(block.Groups["body"].Value, "'([^']+)'")
            .Select(match => match.Groups[1].Value)
            .ToArray();
    }

    private static string FindRepositoryRoot() {
        var directory = new DirectoryInfo(TestContext.CurrentContext.TestDirectory);
        while (directory is not null) {
            if (File.Exists(Path.Combine(directory.FullName, "scripts.sln"))) {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException("Could not locate the repository root.");
    }

    private static string FindManifestPath() {
        var directory = new DirectoryInfo(TestContext.CurrentContext.TestDirectory);
        while (directory is not null) {
            var candidate = Path.Combine(
                directory.FullName,
                "src",
                "AMT.PowerShell.Common",
                "Module",
                "AMT.PowerShell.Common.psd1");
            if (File.Exists(candidate)) {
                return candidate;
            }

            directory = directory.Parent;
        }

        throw new FileNotFoundException("Could not locate AMT.PowerShell.Common.psd1.");
    }
}
