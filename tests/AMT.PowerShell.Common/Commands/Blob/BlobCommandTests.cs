// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using AMT.PowerShell.Common.Commands.Blob;

namespace AMT.PowerShell.Common.Tests.Commands.Blob;

[TestFixture]
[NonParallelizable]
public sealed class BlobCommandTests {
    [TearDown]
    public void TearDown() {
        BlobOperations.FileReaderOverride = null;
        BlobOperations.DirectoryEnumeratorOverride = null;
        BlobOperations.HttpGetXmlOverride = null;
        BlobOperations.HttpHeadMD5Override = null;
        BlobOperations.HttpDownloadOverride = null;
    }

    // ── ParseSasQueryString ──────────────────────────────────────────────────

    [Test]
    public void ParseSasQueryString_ReturnsEmpty_ForEmptyToken() {
        var result = BlobOperations.ParseSasQueryString(string.Empty);
        Assert.That(result, Is.EqualTo(string.Empty));
    }

    [Test]
    public void ParseSasQueryString_ParsesSingleKeyValue() {
        var result = BlobOperations.ParseSasQueryString("sv=2021-06-08");
        Assert.That(result, Is.EqualTo("sv=2021-06-08"));
    }

    [Test]
    public void ParseSasQueryString_JoinsMultipleParamsWithAmpersand() {
        var result = BlobOperations.ParseSasQueryString("sv=2021-06-08&se=2026-12-31");
        Assert.That(result, Is.EqualTo("sv=2021-06-08&se=2026-12-31"));
    }

    [Test]
    public void ParseSasQueryString_UrlEncodesSigValue() {
        // '+' in sig must be percent-encoded so the final URL is valid.
        var result = BlobOperations.ParseSasQueryString("sv=2021&sig=abc+def");
        Assert.That(result, Does.Contain("sig=abc%2Bdef"));
    }

    [Test]
    public void ParseSasQueryString_DoesNotEncodeNonSigValues() {
        var result = BlobOperations.ParseSasQueryString("sv=2021&se=2026-12-31");
        Assert.That(result, Does.Contain("se=2026-12-31"));
    }

    // ── ComputeHash ──────────────────────────────────────────────────────────

    [Test]
    public void ComputeHash_ReturnsBase64MD5_ViaFileReaderOverride() {
        var content = Encoding.UTF8.GetBytes("hello world");
        BlobOperations.FileReaderOverride = _ => content;

#pragma warning disable CA5351
        using var md5 = MD5.Create();
#pragma warning restore CA5351
        var expected = Convert.ToBase64String(md5.ComputeHash(content));

        var result = BlobOperations.ComputeHash("virtual-path.bin");
        Assert.That(result, Is.EqualTo(expected));
    }

    [Test]
    public void ComputeHash_IsDeterministic_ForSameContent() {
        var content = Encoding.UTF8.GetBytes("deterministic");
        BlobOperations.FileReaderOverride = _ => content;

        var r1 = BlobOperations.ComputeHash("a.bin");
        var r2 = BlobOperations.ComputeHash("b.bin");
        Assert.That(r1, Is.EqualTo(r2));
    }

    // ── FindFileByHash ───────────────────────────────────────────────────────

    [Test]
    public void FindFileByHash_ReturnsNull_WhenDirectoryAbsent() {
        var result = BlobOperations.FindFileByHash("anyhash", "/nonexistent-dir-xyz");
        Assert.That(result, Is.Null);
    }

    [Test]
    public void FindFileByHash_ReturnsMatchingPath_WhenHashEquals() {
        var content = Encoding.UTF8.GetBytes("find-me");
        BlobOperations.FileReaderOverride = _ => content;

#pragma warning disable CA5351
        using var md5 = MD5.Create();
#pragma warning restore CA5351
        var hash = Convert.ToBase64String(md5.ComputeHash(content));

        var matchPath = "/dir/match.bin";
        var otherPath = "/dir/other.bin";

        BlobOperations.DirectoryEnumeratorOverride = (_, _) => new[] { matchPath, otherPath };

        var result = BlobOperations.FindFileByHash(hash, "/dir");
        Assert.That(result, Is.EqualTo(matchPath));
    }

    [Test]
    public void FindFileByHash_ReturnsNull_WhenNoFileMatches() {
        BlobOperations.FileReaderOverride = _ => new byte[] { 0xFF };
        BlobOperations.DirectoryEnumeratorOverride = (_, _) => new[] { "/dir/a.bin" };

        var result = BlobOperations.FindFileByHash("not-the-hash", "/dir");
        Assert.That(result, Is.Null);
    }

    [Test]
    public void FindFileByHash_ReturnsNull_WhenDirectoryEmpty() {
        BlobOperations.DirectoryEnumeratorOverride = (_, _) => Array.Empty<string>();

        var result = BlobOperations.FindFileByHash("anyhash", "/dir");
        Assert.That(result, Is.Null);
    }

    // ── ListBlobs ────────────────────────────────────────────────────────────

    [Test]
    public void ListBlobs_ReturnsBlobNames_FromXmlResponse() {
        BlobOperations.HttpGetXmlOverride = _ => @"<?xml version=""1.0"" encoding=""utf-8""?>
<EnumerationResults>
  <Blobs>
    <Blob><Name>fonts/arial.ttf</Name></Blob>
    <Blob><Name>fonts/times.ttf</Name></Blob>
  </Blobs>
  <NextMarker></NextMarker>
</EnumerationResults>";

        var result = BlobOperations.ListBlobs("https://example.blob.core.windows.net/fonts", "sv=2021");
        Assert.That(result, Is.EqualTo(new[] { "fonts/arial.ttf", "fonts/times.ttf" }));
    }

    [Test]
    public void ListBlobs_FollowsPagination_WhenNextMarkerPresent() {
        var callCount = 0;
        BlobOperations.HttpGetXmlOverride = uri => {
            callCount++;
            return callCount == 1
                ? @"<?xml version=""1.0""?>
<EnumerationResults>
  <Blobs><Blob><Name>page1.ttf</Name></Blob></Blobs>
  <NextMarker>token123</NextMarker>
</EnumerationResults>"
                : @"<?xml version=""1.0""?>
<EnumerationResults>
  <Blobs><Blob><Name>page2.ttf</Name></Blob></Blobs>
  <NextMarker></NextMarker>
</EnumerationResults>";
        };

        var result = BlobOperations.ListBlobs("https://example.blob.core.windows.net/c", "sv=2021");
        Assert.Multiple(() => {
            Assert.That(callCount, Is.EqualTo(2));
            Assert.That(result, Is.EqualTo(new[] { "page1.ttf", "page2.ttf" }));
        });
    }

    [Test]
    public void ListBlobs_ReturnsEmpty_WhenContainerHasNoBlobs() {
        BlobOperations.HttpGetXmlOverride = _ => @"<?xml version=""1.0""?>
<EnumerationResults>
  <Blobs></Blobs>
  <NextMarker></NextMarker>
</EnumerationResults>";

        var result = BlobOperations.ListBlobs("https://example.blob.core.windows.net/c", "sv=2021");
        Assert.That(result, Is.Empty);
    }

    // ── GetBlobMD5 ───────────────────────────────────────────────────────────

    [Test]
    public void GetBlobMD5_ReturnsMD5Header_FromOverride() {
        BlobOperations.HttpHeadMD5Override = _ => "abc123==";
        var result = BlobOperations.GetBlobMD5("https://example.blob.core.windows.net/c/blob.bin");
        Assert.That(result, Is.EqualTo("abc123=="));
    }

    [Test]
    public void GetBlobMD5_ReturnsNull_WhenOverrideReturnsNull() {
        BlobOperations.HttpHeadMD5Override = _ => null;
        var result = BlobOperations.GetBlobMD5("https://example.blob.core.windows.net/c/blob.bin");
        Assert.That(result, Is.Null);
    }

    // ── GetFromBlob / DownloadBlob ───────────────────────────────────────────

    [Test]
    public void DownloadBlob_InvokesOverride_WithCorrectArguments() {
        string? capturedUri = null;
        string? capturedPath = null;
        BlobOperations.HttpDownloadOverride = (uri, path) => {
            capturedUri = uri;
            capturedPath = path;
        };

        BlobOperations.DownloadBlob("https://example.blob.core.windows.net/c/blob.bin", "/out/blob.bin");

        Assert.Multiple(() => {
            Assert.That(capturedUri, Is.EqualTo("https://example.blob.core.windows.net/c/blob.bin"));
            Assert.That(capturedPath, Is.EqualTo("/out/blob.bin"));
        });
    }

    // ── Cmdlet integration (via PowerShell runspace) ─────────────────────────

    [Test]
    public void ConvertToSasQueryString_CmdletReturnsExpectedString() {
        using var ps = CreatePowerShell();
        ps.AddCommand("ConvertTo-SasQueryString").AddArgument("sv=2021&sig=abc+def");
        var results = ps.Invoke();

        Assert.Multiple(() => {
            Assert.That(ps.HadErrors, Is.False);
            Assert.That(results, Has.Count.EqualTo(1));
            Assert.That((string)results[0].BaseObject, Does.Contain("sig=abc%2Bdef"));
        });
    }

    [Test]
    public void GetBlobCompatableHash_CmdletReturnsBase64MD5() {
        var content = Encoding.UTF8.GetBytes("cmdlet-test");
        BlobOperations.FileReaderOverride = _ => content;

#pragma warning disable CA5351
        using var md5 = MD5.Create();
#pragma warning restore CA5351
        var expected = Convert.ToBase64String(md5.ComputeHash(content));

        using var ps = CreatePowerShell();
        ps.AddCommand("Get-BlobCompatableHash").AddParameter("Path", "virtual.bin");
        var results = ps.Invoke();

        Assert.Multiple(() => {
            Assert.That(ps.HadErrors, Is.False);
            Assert.That((string)results[0].BaseObject, Is.EqualTo(expected));
        });
    }

    [Test]
    public void FindFileByHash_CmdletReturnsEmpty_WhenNoDirectory() {
        using var ps = CreatePowerShell();
        ps.AddCommand("Find-FileByHash")
          .AddParameter("Hash", "anyhash")
          .AddParameter("Path", "/no-such-dir-xyzzy");
        var results = ps.Invoke();

        Assert.That(ps.HadErrors, Is.False);
        Assert.That(results, Is.Empty);
    }

    // ── Get-FromBlob png semantics ────────────────────────────────────────────

    [Test]
    public void GetFromBlob_AcceptsLegacyBaseURLAndPathAliases() {
        // Legacy call-site: Get-FromBlob -BaseURL ... -Path ... (capital URL, no BlobPath).
        BlobOperations.HttpHeadMD5Override = _ => null;
        BlobOperations.HttpDownloadOverride = (_, _) => { };

        using var ps = CreatePowerShell();
        ps.AddCommand("Get-FromBlob")
          .AddParameter("BaseURL", "https://example.com")
          .AddParameter("Path", "images/wallpaper.png")
          .AddParameter("SasToken", "sv=2021")
          .AddParameter("CachePath", System.IO.Path.GetTempPath());
        ps.Invoke();

        // Binding succeeds when no error is produced.
        Assert.That(ps.HadErrors, Is.False);
    }

    [Test]
    public void GetFromBlob_UsesPngFilter_WhenSearchingCache() {
        // MD5 non-null triggers FindFileByHash; capture the filter passed.
        string? capturedFilter = null;
        BlobOperations.HttpHeadMD5Override = _ => "test-md5==";
        BlobOperations.DirectoryEnumeratorOverride = (_, filter) => {
            capturedFilter = filter;
            return Array.Empty<string>();  // no match → falls through to download
        };
        BlobOperations.HttpDownloadOverride = (_, _) => { };

        using var ps = CreatePowerShell();
        ps.AddCommand("Get-FromBlob")
          .AddParameter("Url", "https://example.com/blob.png")
          .AddParameter("SasToken", "sv=2021")
          .AddParameter("CachePath", System.IO.Path.GetTempPath());
        ps.Invoke();

        Assert.That(capturedFilter, Is.EqualTo("*.png"));
    }

    [Test]
    public void GetFromBlob_DownloadedPathHasPngExtension() {
        // No MD5 → skips cache; download seam captures the target path.
        string? capturedOutPath = null;
        BlobOperations.HttpHeadMD5Override = _ => null;
        BlobOperations.HttpDownloadOverride = (_, outPath) => { capturedOutPath = outPath; };

        using var ps = CreatePowerShell();
        ps.AddCommand("Get-FromBlob")
          .AddParameter("Url", "https://example.com/blob.png")
          .AddParameter("SasToken", "sv=2021")
          .AddParameter("CachePath", System.IO.Path.GetTempPath());
        var results = ps.Invoke();

        Assert.Multiple(() => {
            Assert.That(ps.HadErrors, Is.False);
            Assert.That(capturedOutPath, Does.EndWith(".png"));
            Assert.That(results, Has.Count.EqualTo(1));
            Assert.That((string)results[0].BaseObject, Does.EndWith(".png"));
        });
    }

    [Test]
    public void GetFromBlob_ReturnsCachedPath_WhenPngHashMatches() {
        const string cachedFile = "/cache/existing.png";
        BlobOperations.HttpHeadMD5Override = _ => "cached-md5==";
        BlobOperations.DirectoryEnumeratorOverride = (_, _) => new[] { cachedFile };
        BlobOperations.FileReaderOverride = path => {
            // Return bytes whose MD5 equals "cached-md5=="
            // We set the override to return a consistent hash.
            return System.Text.Encoding.UTF8.GetBytes("cached-content");
        };
        // Recompute expected hash for the cached content bytes
        var cachedBytes = System.Text.Encoding.UTF8.GetBytes("cached-content");
#pragma warning disable CA5351
        using var md5 = System.Security.Cryptography.MD5.Create();
#pragma warning restore CA5351
        var expectedHash = Convert.ToBase64String(md5.ComputeHash(cachedBytes));
        BlobOperations.HttpHeadMD5Override = _ => expectedHash;

        using var ps = CreatePowerShell();
        ps.AddCommand("Get-FromBlob")
          .AddParameter("Url", "https://example.com/blob.png")
          .AddParameter("SasToken", "sv=2021")
          .AddParameter("CachePath", "/cache");
        var results = ps.Invoke();

        Assert.Multiple(() => {
            Assert.That(ps.HadErrors, Is.False);
            Assert.That(results, Has.Count.EqualTo(1));
            Assert.That((string)results[0].BaseObject, Is.EqualTo(cachedFile));
        });
    }

    private static System.Management.Automation.PowerShell CreatePowerShell() {
        var iss = System.Management.Automation.Runspaces.InitialSessionState.CreateDefault2();
        iss.Commands.Add(new System.Management.Automation.Runspaces.SessionStateCmdletEntry(
            "ConvertTo-SasQueryString", typeof(ConvertToSasQueryStringCommand), null));
        iss.Commands.Add(new System.Management.Automation.Runspaces.SessionStateCmdletEntry(
            "Get-BlobCompatableHash", typeof(GetBlobCompatableHashCommand), null));
        iss.Commands.Add(new System.Management.Automation.Runspaces.SessionStateCmdletEntry(
            "Get-BlobMD5", typeof(GetBlobMD5Command), null));
        iss.Commands.Add(new System.Management.Automation.Runspaces.SessionStateCmdletEntry(
            "Get-BlobList", typeof(GetBlobListCommand), null));
        iss.Commands.Add(new System.Management.Automation.Runspaces.SessionStateCmdletEntry(
            "Find-FileByHash", typeof(FindFileByHashCommand), null));
        iss.Commands.Add(new System.Management.Automation.Runspaces.SessionStateCmdletEntry(
            "Get-FromBlob", typeof(GetFromBlobCommand), null));

        var runspace = System.Management.Automation.Runspaces.RunspaceFactory.CreateRunspace(iss);
        runspace.Open();

        var ps = System.Management.Automation.PowerShell.Create();
        ps.Runspace = runspace;
        return ps;
    }
}
