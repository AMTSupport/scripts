// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.IO;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Blob;

/// <summary>Download a blob from Azure Blob Storage to a local cache directory, returning the local file path.</summary>
/// <remarks>
/// <para>Checks the cache before downloading: computes the blob's Content-MD5 via <c>Get-BlobMD5</c> and
/// searches <c>CachePath</c> for an existing file with a matching hash using <c>Find-FileByHash</c>.
/// Returns the existing path without re-downloading when a match is found.</para>
/// <para>When no cached copy exists the blob is downloaded to a randomly-named <c>.png</c> file inside
/// <c>CachePath</c> and that path is returned.</para>
/// <para>Two parameter sets are supported: <c>ByDirectUrl</c> (a fully-qualified blob URL) and
/// <c>ByUrlAndPath</c> (a container base URL combined with a relative blob path).</para>
/// </remarks>
/// <example>
/// <code>Get-FromBlob -Url 'https://account.blob.core.windows.net/c/image.png' -CachePath 'C:\Cache' -SasToken $token</code>
/// Downloads the blob if not already cached, returns the local file path.
/// </example>
/// <example>
/// <code>Get-FromBlob -BaseURL 'https://account.blob.core.windows.net/fonts' -BlobPath 'Arial.ttf' -CachePath 'C:\Cache' -SasToken $token</code>
/// Constructs the blob URL from base URL and path, then downloads or returns from cache.
/// </example>
[Cmdlet(VerbsCommon.Get, "FromBlob", DefaultParameterSetName = ByDirectUrl)]
[OutputType(typeof(string))]
public sealed class GetFromBlobCommand : PSCmdlet {
    private const string ByDirectUrl = "ByDirectUrl";
    private const string ByUrlAndPath = "ByUrlAndPath";

    /// <summary>The full blob URL (excluding the SAS query string), used in the <c>ByDirectUrl</c> parameter set.</summary>
    [Parameter(Mandatory = true, ParameterSetName = ByDirectUrl, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string Url { get; set; } = string.Empty;

    /// <summary>The base container URL (no trailing slash), used with <c>BlobPath</c> in the <c>ByUrlAndPath</c> parameter set.</summary>
    [Parameter(Mandatory = true, ParameterSetName = ByUrlAndPath, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string BaseURL { get; set; } = string.Empty;

    /// <summary>The relative path of the blob within the container, combined with <c>BaseURL</c>.</summary>
    [Parameter(Mandatory = true, ParameterSetName = ByUrlAndPath, Position = 1)]
    [ValidateNotNullOrEmpty]
    [Alias("Path")]
    public string BlobPath { get; set; } = string.Empty;

    /// <summary>Local directory where downloaded blobs are cached; created automatically if it does not exist.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    public string CachePath { get; set; } = string.Empty;

    /// <summary>The raw SAS token used to authenticate blob requests; converted internally via <c>ConvertTo-SasQueryString</c>.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    public string SasToken { get; set; } = string.Empty;

    protected override void ProcessRecord() {
        var sasQuery = BlobOperations.ParseSasQueryString(this.SasToken);

        string blobUri;
        if (this.ParameterSetName == ByDirectUrl) {
            blobUri = $"{this.Url}?{sasQuery}";
        } else {
            var combined = this.BaseURL.TrimEnd('/') + "/" + this.BlobPath.TrimStart('/');
            blobUri = $"{combined}?{sasQuery}";
        }

        var md5 = BlobOperations.GetBlobMD5(blobUri);
        if (md5 is not null) {
            // Restrict cache search to *.png to match legacy Set-Wallpaper semantics.
            var existing = BlobOperations.FindFileByHash(md5, this.CachePath, "*.png");
            if (existing is not null) {
                this.WriteObject(existing);
                return;
            }
        }

        Directory.CreateDirectory(this.CachePath);
        // Append .png to match legacy blob download filename convention.
        var outPath = Path.Combine(this.CachePath, Path.GetRandomFileName() + ".png");
        BlobOperations.DownloadBlob(blobUri, outPath);
        this.WriteObject(outPath);
    }
}
