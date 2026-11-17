// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using AMT.PowerShell.Common.Commands.Cache;

namespace AMT.PowerShell.Common.Tests.Commands.Cache;

[TestFixture]
[NonParallelizable]
public sealed class CacheCommandTests {
    private string _cacheFolder = string.Empty;

    [SetUp]
    public void SetUp() {
        _cacheFolder = Path.Combine(Path.GetTempPath(), $"PSCacheTest-{Guid.NewGuid():N}");
        CacheOperations.CacheFolderOverride = _cacheFolder;
    }

    [TearDown]
    public void TearDown() {
        CacheOperations.CacheFolderOverride = null;
        TryDeleteDirectory(_cacheFolder);
    }

    // ── Get-CachedLocation ────────────────────────────────────────────────

    [Test]
    public void GetCachedLocation_ReturnsExpectedPath() {
        const string name = "path-check";
        var expected = Path.Combine(_cacheFolder, $"Cached-{name}");

        var r = Invoke("Get-CachedLocation", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create("return 'x'"));
        });

        Assert.That(r.Output, Has.Count.EqualTo(1));
        Assert.That(r.Output[0].BaseObject, Is.EqualTo(expected));
    }

    [Test]
    public void GetCachedLocation_CreatesFileWithCreateBlockContent() {
        var name = $"create-{Guid.NewGuid():N}";
        var content = Guid.NewGuid().ToString();
        var path = Path.Combine(_cacheFolder, $"Cached-{name}");

        Invoke("Get-CachedLocation", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create($"return '{content}'"));
        });

        Assert.Multiple(() => {
            Assert.That(File.Exists(path), Is.True);
            Assert.That(File.ReadAllText(path), Is.EqualTo(content));
        });
    }

    [Test]
    public void GetCachedLocation_DoesNotOverrideExistingFile() {
        var name = $"no-override-{Guid.NewGuid():N}";
        var original = Guid.NewGuid().ToString();
        var path = Path.Combine(_cacheFolder, $"Cached-{name}");

        Invoke("Get-CachedLocation", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create($"return '{original}'"));
        });

        Invoke("Get-CachedLocation", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create($"return '{Guid.NewGuid()}'"));
        });

        Assert.That(File.ReadAllText(path), Is.EqualTo(original));
    }

    [Test]
    public void GetCachedLocation_NoCacheOverwritesExistingFile() {
        var name = $"nocache-{Guid.NewGuid():N}";
        var original = Guid.NewGuid().ToString();
        var replacement = Guid.NewGuid().ToString();
        var path = Path.Combine(_cacheFolder, $"Cached-{name}");

        Invoke("Get-CachedLocation", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create($"return '{original}'"));
        });

        Invoke("Get-CachedLocation", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create($"return '{replacement}'"));
            ps.AddParameter("NoCache", true);
        });

        Assert.That(File.ReadAllText(path), Is.EqualTo(replacement));
    }

    [Test]
    public void GetCachedLocation_MaxAgeInvalidatesOldCache() {
        var name = $"maxage-{Guid.NewGuid():N}";
        var original = Guid.NewGuid().ToString();
        var replacement = Guid.NewGuid().ToString();
        var path = Path.Combine(_cacheFolder, $"Cached-{name}");

        Invoke("Get-CachedLocation", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create($"return '{original}'"));
        });

        // Backdate the file so it appears older than 1 second.
        File.SetLastWriteTimeUtc(path, DateTime.UtcNow.AddSeconds(-5));

        Invoke("Get-CachedLocation", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create($"return '{replacement}'"));
            ps.AddParameter("MaxAge", TimeSpan.FromSeconds(1));
        });

        Assert.That(File.ReadAllText(path), Is.EqualTo(replacement));
    }

    [Test]
    public void GetCachedLocation_MaxAgeKeepsFreshCache() {
        var name = $"maxage-fresh-{Guid.NewGuid():N}";
        var original = Guid.NewGuid().ToString();
        var path = Path.Combine(_cacheFolder, $"Cached-{name}");

        Invoke("Get-CachedLocation", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create($"return '{original}'"));
        });

        Invoke("Get-CachedLocation", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create($"return '{Guid.NewGuid()}'"));
            ps.AddParameter("MaxAge", TimeSpan.FromHours(1));
        });

        Assert.That(File.ReadAllText(path), Is.EqualTo(original));
    }

    [Test]
    public void GetCachedLocation_IsValidBlockFalseReplacesCache() {
        var name = $"valid-false-{Guid.NewGuid():N}";
        var original = Guid.NewGuid().ToString();
        var replacement = Guid.NewGuid().ToString();
        var path = Path.Combine(_cacheFolder, $"Cached-{name}");

        Invoke("Get-CachedLocation", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create($"return '{original}'"));
        });

        Invoke("Get-CachedLocation", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create($"return '{replacement}'"));
            ps.AddParameter("IsValidBlock", ScriptBlock.Create("param($Path) return $false"));
        });

        Assert.That(File.ReadAllText(path), Is.EqualTo(replacement));
    }

    [Test]
    public void GetCachedLocation_IsValidBlockTrueKeepsCache() {
        var name = $"valid-true-{Guid.NewGuid():N}";
        var original = Guid.NewGuid().ToString();
        var path = Path.Combine(_cacheFolder, $"Cached-{name}");

        Invoke("Get-CachedLocation", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create($"return '{original}'"));
        });

        Invoke("Get-CachedLocation", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create($"return '{Guid.NewGuid()}'"));
            ps.AddParameter("IsValidBlock", ScriptBlock.Create("param($Path) return $true"));
        });

        Assert.That(File.ReadAllText(path), Is.EqualTo(original));
    }

    // ── Get-CachedContent ─────────────────────────────────────────────────

    [Test]
    public void GetCachedContent_WriteBlock_IsPassedThroughToFileCreation() {
        var name = $"cc-wb-{Guid.NewGuid():N}";
        var sentinel = Path.Combine(_cacheFolder, $"cc-wb-sentinel-{name}");
        var esc = sentinel.Replace("'", "''");

        // WriteBlock writes the content to the cache path AND marks a sentinel so we know it ran.
        var r = Invoke("Get-CachedContent", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create("return '{\"K\":\"V\"}'"));
            ps.AddParameter("WriteBlock", ScriptBlock.Create(
                $"param($p, $c) $c | Set-Content -Path $p -Encoding UTF8; Set-Content -Path '{esc}' -Value 'wb-fired'"));
        });

        Assert.That(r.ThrownException, Is.Null);
        Assert.Multiple(() => {
            Assert.That(r.Output, Has.Count.EqualTo(1));
            Assert.That(File.Exists(sentinel), Is.True, "WriteBlock must be invoked");
        });
    }

    // ── Get-CachedLocation WriteBlock ─────────────────────────────────────

    [Test]
    public void GetCachedLocation_WriteBlock_IsInvokedInsteadOfDefaultWrite() {
        var name = $"wb-called-{Guid.NewGuid():N}";
        // Write a sentinel into a side-channel file so we can confirm the WriteBlock ran.
        var sentinel = Path.Combine(_cacheFolder, $"wb-sentinel-{name}");
        var escapedSentinel = sentinel.Replace("'", "''");

        var r = Invoke("Get-CachedLocation", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create("return 'wb-content'"));
            ps.AddParameter("WriteBlock", ScriptBlock.Create(
                $"param($p, $c) Set-Content -Path '{escapedSentinel}' -Value 'called'"));
        });

        Assert.That(r.ThrownException, Is.Null);
        Assert.Multiple(() => {
            Assert.That(r.Output, Has.Count.EqualTo(1));
            Assert.That(File.Exists(sentinel), Is.True, "WriteBlock sentinel file must exist");
            Assert.That(File.ReadAllText(sentinel).Trim(), Is.EqualTo("called"));
        });
    }

    [Test]
    public void GetCachedLocation_WriteBlock_PreservesBinaryContent() {
        var name = $"wb-binary-{Guid.NewGuid():N}";
        var cachePath = Path.Combine(_cacheFolder, $"Cached-{name}");
        var expectedBytes = new byte[] { 1, 2, 3, 0xFE, 0xFF };

        // PS enumerates byte[] through the pipeline; each byte arrives as a separate PSObject.
        // The WriteBlock receives the collected items and writes them raw with WriteAllBytes.
        var r = Invoke("Get-CachedLocation", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create("return [byte[]](1, 2, 3, 254, 255)"));
            ps.AddParameter("WriteBlock", ScriptBlock.Create(
                "param([string]$p, $c) [System.IO.File]::WriteAllBytes($p, [byte[]]$c)"));
        });

        Assert.That(r.ThrownException, Is.Null);
        Assert.Multiple(() => {
            Assert.That(File.Exists(cachePath), Is.True);
            Assert.That(File.ReadAllBytes(cachePath), Is.EqualTo(expectedBytes));
        });
    }

    [Test]
    public void GetCachedContent_CreatesCacheAndReturnsParsedJson() {
        var name = $"content-create-{Guid.NewGuid():N}";

        var r = Invoke("Get-CachedContent", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create("return '{\"NewCache\":\"Content\"}'"));
        });

        Assert.That(r.Output, Has.Count.EqualTo(1));
        var ht = r.Output[0].BaseObject as Hashtable;
        Assert.That(ht, Is.Not.Null);
        Assert.That(ht!["NewCache"], Is.EqualTo("Content"));
    }

    [Test]
    public void GetCachedContent_ReturnsCachedContentOnSecondCall() {
        var name = $"content-reuse-{Guid.NewGuid():N}";

        Invoke("Get-CachedContent", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create("return '{\"NewCache\":\"OldContent\"}'"));
        });

        var r = Invoke("Get-CachedContent", ps => {
            ps.AddParameter("Name", name);
            ps.AddParameter("CreateBlock", ScriptBlock.Create("return '{\"NewCache\":\"NewContent\"}'"));
        });

        var ht = r.Output[0].BaseObject as Hashtable;
        Assert.That(ht!["NewCache"], Is.EqualTo("OldContent"));
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private static InvocationResult Invoke(string cmdlet, Action<System.Management.Automation.PowerShell> configure) {
        var iss = InitialSessionState.CreateDefault2();
        iss.Commands.Add(new SessionStateCmdletEntry("Get-CachedLocation", typeof(GetCachedLocationCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Get-CachedContent", typeof(GetCachedContentCommand), null));

        using var runspace = RunspaceFactory.CreateRunspace(iss);
        runspace.Open();

        using var ps = System.Management.Automation.PowerShell.Create();
        ps.Runspace = runspace;
        ps.AddCommand(cmdlet);
        configure(ps);

        var output = new Collection<PSObject>();
        RuntimeException? thrown = null;

        try {
            ps.Invoke(null, output);
        } catch (RuntimeException ex) {
            thrown = ex;
        }

        return new InvocationResult(output, [.. ps.Streams.Error], thrown);
    }

    private static void TryDeleteDirectory(string path) {
        try {
            if (Directory.Exists(path)) Directory.Delete(path, recursive: true);
        } catch { }
    }

    private sealed record InvocationResult(
        Collection<PSObject> Output,
        IReadOnlyList<ErrorRecord> Errors,
        RuntimeException? ThrownException);
}
