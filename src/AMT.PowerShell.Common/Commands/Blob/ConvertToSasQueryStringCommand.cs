// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Blob;

/// <summary>Parse a raw SAS token into a URL-encoded query string.</summary>
/// <remarks>
/// Extracts key-value pairs from the token, URL-encodes the <c>sig</c> value,
/// and reassembles them as an <c>application/x-www-form-urlencoded</c> query string
/// suitable for appending to an Azure Blob Storage URL.
/// </remarks>
/// <example>
/// <code>$qs = ConvertTo-SasQueryString -SasToken $env:BLOB_SAS_TOKEN</code>
/// Returns the parsed query string ready to append with <c>?</c> to a container URL.
/// </example>
/// <example>
/// <code>$env:BLOB_SAS_TOKEN | ConvertTo-SasQueryString</code>
/// Accepts the token from the pipeline.
/// </example>
[Cmdlet(VerbsData.ConvertTo, "SasQueryString")]
[OutputType(typeof(string))]
public sealed class ConvertToSasQueryStringCommand : Cmdlet {
    /// <summary>The raw SAS token string to parse into a query string.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    [ValidateNotNullOrEmpty]
    public string SasToken { get; set; } = string.Empty;

    protected override void ProcessRecord() =>
        this.WriteObject(BlobOperations.ParseSasQueryString(this.SasToken));
}
