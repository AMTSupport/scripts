// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace AMT.PowerShell.Common.Commands.Blob;

internal static class BlobOperations {
    private static readonly HttpClient SharedHttpClient = new();

    // Injectable seams for testing
    internal static Func<string, byte[]>? FileReaderOverride { get; set; }
    internal static Func<string, string, IEnumerable<string>>? DirectoryEnumeratorOverride { get; set; }
    internal static Func<string, string>? HttpGetXmlOverride { get; set; }
    internal static Func<string, string?>? HttpHeadMD5Override { get; set; }
    internal static Action<string, string>? HttpDownloadOverride { get; set; }

    // Parse SAS token into a URL query string, URL-encoding the sig component.
    internal static string ParseSasQueryString(string sasToken) {
        var regex = new Regex(@"(?<key>[A-Za-z]+)=(?<value>[A-Za-z\d\-:/+=]+)&?");
        var matches = regex.Matches(sasToken);

        var parts = new List<string>(matches.Count);
        foreach (Match match in matches) {
            var key = match.Groups["key"].Value;
            var rawValue = match.Groups["value"].Value;
            var value = key.Equals("sig", StringComparison.OrdinalIgnoreCase)
                ? Uri.EscapeDataString(rawValue)
                : rawValue;
            parts.Add($"{key}={value}");
        }

        return string.Join("&", parts);
    }

    // Compute MD5 and return as base64 — matches Azure blob Content-MD5 format.
    internal static string ComputeHash(string filePath) {
        var bytes = FileReaderOverride is not null
            ? FileReaderOverride(filePath)
            : File.ReadAllBytes(filePath);

#pragma warning disable CA5351 // MD5 required for Azure blob compatibility
        using var md5 = MD5.Create();
#pragma warning restore CA5351
        var hash = md5.ComputeHash(bytes);
        return Convert.ToBase64String(hash);
    }

    // Scan directory for a file whose blob-compatible MD5 matches hash.
    // Returns full path of first match, or null.
    internal static string? FindFileByHash(string hash, string directory, string filter = "*") {
        IEnumerable<string> files;
        if (DirectoryEnumeratorOverride is not null) {
            files = DirectoryEnumeratorOverride(directory, filter);
        } else {
            if (!Directory.Exists(directory)) {
                return null;
            }
            files = Directory.EnumerateFiles(directory, filter, SearchOption.TopDirectoryOnly);
        }

        foreach (var filePath in files) {
            var fileHash = ComputeHash(filePath);
            if (string.Equals(fileHash, hash, StringComparison.Ordinal)) {
                return filePath;
            }
        }

        return null;
    }

    // Enumerate all blobs in an Azure Blob Storage container, following pagination.
    internal static string[] ListBlobs(string containerUrl, string sasQueryString) {
        var allBlobs = new List<string>();
        var marker = string.Empty;

        do {
            var listParams = "restype=container&comp=list&maxresults=500";
            if (!string.IsNullOrEmpty(marker)) {
                listParams += $"&marker={marker}";
            }

            var uri = $"{containerUrl}?{listParams}&{sasQueryString}";
            var xml = GetXml(uri);
            var doc = XDocument.Parse(xml);

            var ns = doc.Root?.Name.Namespace ?? XNamespace.None;
            foreach (var blob in doc.Descendants(ns + "Blob")) {
                var name = blob.Element(ns + "Name")?.Value;
                if (name is not null) {
                    allBlobs.Add(name);
                }
            }

            marker = doc.Descendants(ns + "NextMarker").FirstOrDefault()?.Value ?? string.Empty;
        } while (!string.IsNullOrEmpty(marker));

        return allBlobs.ToArray();
    }

    // Retrieve the Content-MD5 header for a blob via HEAD request.
    internal static string? GetBlobMD5(string blobUri) {
        if (HttpHeadMD5Override is not null) {
            return HttpHeadMD5Override(blobUri);
        }

        using var request = new HttpRequestMessage(HttpMethod.Head, blobUri);
        using var response = SharedHttpClient.SendAsync(request).GetAwaiter().GetResult();
        response.EnsureSuccessStatusCode();

        if (response.Content.Headers.TryGetValues("Content-MD5", out var values)) {
            return values.FirstOrDefault();
        }

        return null;
    }

    // Download blob content to outPath.
    internal static void DownloadBlob(string blobUri, string outPath) {
        if (HttpDownloadOverride is not null) {
            HttpDownloadOverride(blobUri, outPath);
            return;
        }

        var bytes = SharedHttpClient.GetByteArrayAsync(blobUri).GetAwaiter().GetResult();
        File.WriteAllBytes(outPath, bytes);
    }

    private static string GetXml(string uri) {
        return HttpGetXmlOverride is not null
            ? HttpGetXmlOverride(uri)
            : SharedHttpClient.GetStringAsync(uri).GetAwaiter().GetResult();
    }
}
