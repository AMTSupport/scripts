// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections.Concurrent;
using Compiler;
using Microsoft.CodeAnalysis.CSharp.Syntax;

[SetUpFixture]
[System.Diagnostics.CodeAnalysis.SuppressMessage(
    "Design",
    "CA1050:Declare types in namespaces",
    Justification = "Required for NUnit to run no matter the namespace."
)]
public sealed class GlobalSetup {
    public static ConcurrentBag<string> RequiresCleanup { get; } = [];

    [OneTimeSetUp]
    public static void Setup() => Program.SetupLogger(new Program.Options() {
        Verbosity = 3
    });

    [OneTimeTearDown]
    public static void Teardown() {
        foreach (var file in RequiresCleanup) {
            if (Directory.Exists(file)) {
                Directory.Delete(file, true);
            } else if (File.Exists(file)) {
                File.Delete(file);
            }
        }
    }
}
