// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.IO.Compression;
using System.Security.Cryptography;
using Compiler.Module;
using Compiler.Module.Resolvable;
using Compiler.Requirements;
using LanguageExt;
using LanguageExt.Common;
using LanguageExt.UnsafeValueAccess;
using Moq;

namespace Compiler.Test.Module.Resolvable;

[TestFixture]
public class ResolvableRemoteModuleTests {
    private ResolvableRemoteModule ResolvableRemoteModule;

    [SetUp]
    public void Setup() {
        var moduleSpec = new ModuleSpec("PSReadLine", requiredVersion: new Version(2, 3, 5));
        this.ResolvableRemoteModule = new Mock<ResolvableRemoteModule>(moduleSpec) {
            CallBase = true
        }.Object;

        if (Directory.Exists(this.ResolvableRemoteModule.CachePath)) {
            Directory.Delete(this.ResolvableRemoteModule.CachePath, true); // Clean up any previous caches
        }
    }

    [Test]
    public void CachePath_IsCorrect() {
        var cachePath = this.ResolvableRemoteModule.CachePath;
        Assert.That(cachePath, Is.EqualTo(Path.Join(Path.GetTempPath(), "PowerShellGet\\PSReadLine")));
    }

    [Test]
    public void GetModuleMatchFor_IsCorrect() {
        var moduleMatch = this.ResolvableRemoteModule.GetModuleMatchFor(new ModuleSpec("PSReadLine"));
        Assert.That(moduleMatch, Is.EqualTo(ModuleMatch.Stricter));
    }

    [Test]
    public async Task ResolveRequirements() {
        var result = await this.ResolvableRemoteModule.ResolveRequirements();
        var requirements = this.ResolvableRemoteModule.Requirements;

        Assert.Multiple(() => {
            Assert.That(result, Is.EqualTo(Option<Error>.None));
            Assert.That(requirements.GetRequirements(), Has.Count.EqualTo(1));
            Assert.That(() => ((PSVersionRequirement)requirements.GetRequirements()[0]).Version, Is.EqualTo(new Version(5, 0)));
        });
    }

    [TestCase(
        [new string?[3] { "2.3.5", null, null }, new string[] { "2.3.5" }, "PSReadLine.2.3.5.nupkg"],
        Description = "Selects the required version from a single cached file"
    )]
    [TestCase(
        [new string?[3] { null, "2.3.5", null }, new string[] { "2.3.5" }, "PSReadLine.2.3.5.nupkg"],
        Description = "Selects the minimum version from a single cached file"
    )]
    [TestCase(
        [new string?[3] { "2.3.5", null, null }, new string[] { "2.3.2", "2.3.5", "2.3.7", "2.4.0" }, "PSReadLine.2.3.5.nupkg"],
        Description = "Selects the required version from multiple cached files"
    )]
    [TestCase(
        [new string?[3] { null, "2.3.5", null }, new string[] { "2.3.2", "2.3.5", "2.3.7", "2.4.0" }, "PSReadLine.2.4.0.nupkg"],
        Description = "Selects the latest version because the minimum version is less than"
    )]
    [TestCase(
        [new string?[3] { null, null, "2.3.6" }, new string[] { "2.3.2", "2.3.5", "2.3.7", "2.4.0" }, "PSReadLine.2.3.5.nupkg"],
        Description = "Selects the closest to the maximum version from multiple cached files"
    )]
    [TestCase(
        [new string?[3] { null, null, "2.3.5" }, new string[] { "2.3.2", "2.3.5", "2.3.7", "2.4.0" }, "PSReadLine.2.3.5.nupkg"],
        Description = "Selects the maximum version from multiple cached files"
    )]
    [TestCase(
        [new string?[3] { null, "2.3.4", "2.3.9" }, new string[] { "2.3.2", "2.3.5", "2.3.7", "2.4.0" }, "PSReadLine.2.3.7.nupkg"],
        Description = "Selects the between the minimum and maximum version from multiple cached files"
    )]
    [TestCase(
        [new string?[3] { null, null, null }, new string[] { "2.3.2", "2.3.5", "2.3.7", "2.4.0" }, "PSReadLine.2.4.0.nupkg"],
        Description = "Selects the latest version with no version constraints"
    )]
    public async Task FindCachedResult(
        string?[] moduleVersion,
        string[] cachedVersions,
        string expectedSelectedVersion
    ) {
        var moduleTuple = (moduleVersion[0], moduleVersion[1], moduleVersion[2]);

        var moduleSpec = moduleTuple switch {
            (null, null, null) => new ModuleSpec("PSReadLine"),
            (string req, _, _) => new ModuleSpec("PSReadLine", requiredVersion: new Version(req)),
            (_, string minimum, null) => new ModuleSpec("PSReadLine", minimumVersion: new Version(minimum)),
            (_, null, string maximum) => new ModuleSpec("PSReadLine", maximumVersion: new Version(maximum)),
            (_, string minimum, string maximum) => new ModuleSpec("PSReadLine", minimumVersion: new Version(minimum), maximumVersion: new Version(maximum))
        };

        var module = new ResolvableRemoteModule(moduleSpec);
        TestData.CreateDummyCacheFiles(module, cachedVersions);

        var result = await module.FindCachedResult();
        Assert.Multiple(() => {
            Assert.That(result.IsSome, Is.True);
            Assert.That(result.ValueUnsafe(), Is.EqualTo(Path.Join(module.CachePath, expectedSelectedVersion)));
        });
    }

    [Test]
    public async Task FindCachedResult_IgnoresInvalidVersions() {
        TestData.CreateDummyCacheFiles(this.ResolvableRemoteModule, "invalidversion");
        var result = await this.ResolvableRemoteModule.FindCachedResult();
        Assert.That(result, Is.EqualTo(Option<string>.None));
    }

    [Test, NonParallelizable]
    public async Task FindCachedResult_WaitsForTask() {
        var manualEvent = new ManualResetEventSlim(false);
        var task = Task.Run(async () => {
            await manualEvent.WaitHandle.WaitOneAsync(-1, CancellationToken.None);
            return Prelude.Some("testfile");
        });

        this.ResolvableRemoteModule.CachedFile = Prelude.Atom(Either<Option<string>, Task<Option<string>>>.Right(task));
        var resultTask = this.ResolvableRemoteModule.FindCachedResult();

        await Task.Delay(250);

        Assert.Multiple(async () => {
            Assert.That(task.IsCompleted, Is.False);
            Assert.That(resultTask.IsCompleted, Is.False);
            Assert.That(this.ResolvableRemoteModule.CachedFile.Value, Is.EqualTo(task));

            manualEvent.Set();
            await task;
            this.ResolvableRemoteModule.CachedFile.Swap(_ => task);

            Assert.That(resultTask.IsCompleted, Is.True);
            Assert.That(resultTask.Result, Is.EqualTo(Prelude.Some("testfile")));
        });
    }

    [Test]
    public void FindCachedResult_CreatesEventWhenFoundAndSetsCache() {
        TestData.CreateDummyCacheFiles(this.ResolvableRemoteModule, "2.3.5");

        var resultTask = this.ResolvableRemoteModule.FindCachedResult();
        Assert.Multiple(() => {
            Assert.That(async () => (await resultTask).Unwrap(), Is.EqualTo(Path.Join(this.ResolvableRemoteModule.CachePath, "PSReadLine.2.3.5.nupkg")));

            Assert.That(this.ResolvableRemoteModule.CachedFile!.Value.IsLeft, Is.True);
            Assert.That(((Option<string>)this.ResolvableRemoteModule.CachedFile!.Value).Unwrap(), Is.EqualTo(Path.Join(this.ResolvableRemoteModule.CachePath, "PSReadLine.2.3.5.nupkg")));
        });
    }

    [Test, Repeat(2)]
    public async Task CacheResult_DownloadsValidFile() {
        if (TestContext.CurrentContext.CurrentRepeatCount % 2 == 0) {
            // Allows us to cover the last branch of swapping the either method
            // this.ResolvableRemoteModule.CachedFile = Prelude.Atom(Either<string, Task<Option<string>>>.Right(Task.FromResult(Option<string>.None)));
        }

        await Assert.MultipleAsync(async () => {
            var result = (await this.ResolvableRemoteModule.CacheResult()).ThrowIfFail();
            Assert.That(File.Exists(result), Is.True);
            Assert.That(Path.GetDirectoryName(result), Is.EqualTo(this.ResolvableRemoteModule.CachePath));

            using var reader = File.OpenRead(result);
            Assert.That(reader.Length, Is.GreaterThan(0));

            using var hasher = SHA256.Create();
            var hash = hasher.ComputeHash(reader);
            var hashString = Convert.ToHexString(hash);
            Assert.That(hashString, Is.EqualTo("3A9430315469465407F8D7830653BD2415A994625CE92722E5820A8286B7AD27"));

            Assert.That(() => new ZipArchive(reader, ZipArchiveMode.Read), Throws.Nothing);
        });
    }

    [TestCase([null, null, null], ExpectedResult = null)]
    [TestCase(["2.3.5", null, null], ExpectedResult = "2.3.5")]
    [TestCase([null, "2.3.5", null], ExpectedResult = "[2.3.5,)")]
    [TestCase([null, null, "2.3.5"], ExpectedResult = "(,2.3.5]")]
    [TestCase([null, "2.3.2", "2.3.5"], ExpectedResult = "[2.3.2,2.3.5]")]
    [TestCase(["2.3.2", "2.3.5", "2.3.5"], ExpectedResult = "2.3.2")]
    public string? ConvertVersionParameters(
        string? requiredVersion,
        string? minimumVersion,
        string? maximumVersion
    ) => ResolvableRemoteModule.ConvertVersionParameters(requiredVersion, minimumVersion, maximumVersion);
}

file static class TestData {
    public static void CreateDummyCacheFiles(
        ResolvableRemoteModule resolvableRemoteModule,
        params string[] versions
    ) {
        Directory.CreateDirectory(resolvableRemoteModule.CachePath);

        foreach (var version in versions) {
            File.Create(Path.Join(resolvableRemoteModule.CachePath, $"{resolvableRemoteModule.ModuleSpec.Name}.{version}.nupkg")).Dispose();
        }
    }
}
