// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Blob;

/// <summary>Retrieve the Content-MD5 header value for an Azure Blob Storage resource.</summary>
/// <remarks>
/// Issues an HTTP HEAD request to <c>BlobUri</c> and returns the <c>Content-MD5</c> response header
/// as a base64-encoded string.
/// Returns <see langword="null"/> when the header is absent.
/// Use the result with <c>Find-FileByHash</c> to check whether a blob is already cached locally.
/// </remarks>
/// <example>
/// <code>$md5 = Get-BlobMD5 -BlobUri "https://account.blob.core.windows.net/c/file.png?$qs"</code>
/// Returns the base64-encoded MD5 of the blob, or nothing if the header is missing.
/// </example>
[Cmdlet(VerbsCommon.Get, "BlobMD5")]
[OutputType(typeof(string))]
public sealed class GetBlobMD5Command : Cmdlet {
    /// <summary>The full URI of the blob, including any required SAS query string.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string BlobUri { get; set; } = string.Empty;

    protected override void ProcessRecord() =>
        this.WriteObject(BlobOperations.GetBlobMD5(this.BlobUri));
}
