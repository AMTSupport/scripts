// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Blob;

/// <summary>Compute the base64-encoded MD5 hash of a local file, matching Azure Blob Storage's Content-MD5 format.</summary>
/// <remarks>
/// Reads the file at <c>Path</c> as a byte array, computes its MD5 digest, and returns the result
/// as a base64 string — the same representation Azure uses for the <c>Content-MD5</c> response header.
/// Use this to compare a local file against a blob's server-side hash without downloading the blob.
/// </remarks>
/// <example>
/// <code>$hash = Get-BlobCompatableHash -Path 'C:\Downloads\image.png'</code>
/// Returns the base64-encoded MD5 hash of the file.
/// </example>
[Cmdlet(VerbsCommon.Get, "BlobCompatableHash")]
[OutputType(typeof(string))]
public sealed class GetBlobCompatableHashCommand : Cmdlet {
    /// <summary>Path to the local file to hash.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string Path { get; set; } = string.Empty;

    protected override void ProcessRecord() =>
        this.WriteObject(BlobOperations.ComputeHash(this.Path));
}
