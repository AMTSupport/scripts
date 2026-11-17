// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Blob;

/// <summary>Search a directory for a file whose blob-compatible MD5 hash matches the given value.</summary>
/// <remarks>
/// Iterates over files in <c>Path</c> that match <c>Filter</c>, computes the base64-encoded
/// MD5 hash of each using <see cref="BlobOperations.ComputeHash"/>, and returns the full path
/// of the first file whose hash equals <c>Hash</c>.
/// Returns nothing (no pipeline output) when no matching file is found.
/// </remarks>
/// <example>
/// <code>Find-FileByHash -Hash $md5 -Path 'C:\Cache' -Filter '*.png'</code>
/// Returns the full path of the first PNG in <c>C:\Cache</c> whose hash matches <c>$md5</c>.
/// </example>
[Cmdlet(VerbsCommon.Find, "FileByHash")]
[OutputType(typeof(string))]
public sealed class FindFileByHashCommand : Cmdlet {
    /// <summary>The base64-encoded MD5 hash to match against files in <c>Path</c>.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string Hash { get; set; } = string.Empty;

    /// <summary>The directory to search for matching files.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    public string Path { get; set; } = string.Empty;

    /// <summary>Wildcard filter applied to filenames when enumerating <c>Path</c>; defaults to <c>*</c>.</summary>
    [Parameter]
    public string Filter { get; set; } = "*";

    protected override void ProcessRecord() {
        var result = BlobOperations.FindFileByHash(this.Hash, this.Path, this.Filter);
        if (result is not null) {
            this.WriteObject(result);
        }
    }
}
