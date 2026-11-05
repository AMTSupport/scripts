// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.Blob;

/// <summary>Return the names of all blobs in an Azure Blob Storage container.</summary>
/// <remarks>
/// Issues paginated <c>comp=list</c> requests against the container, following
/// <c>NextMarker</c> tokens until all pages are retrieved.
/// Each blob name is emitted individually to the pipeline.
/// </remarks>
/// <example>
/// <code>Get-BlobList -ContainerUrl 'https://account.blob.core.windows.net/fonts' -SasQueryString $qs</code>
/// Returns the names of every blob in the container.
/// </example>
[Cmdlet(VerbsCommon.Get, "BlobList")]
[OutputType(typeof(string[]))]
public sealed class GetBlobListCommand : Cmdlet {
    /// <summary>The base URL of the Azure Blob Storage container (no trailing slash, no query string).</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string ContainerUrl { get; set; } = string.Empty;

    /// <summary>The pre-parsed SAS query string used to authenticate the request; obtained from <c>ConvertTo-SasQueryString</c>.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    public string SasQueryString { get; set; } = string.Empty;

    protected override void ProcessRecord() =>
        this.WriteObject(BlobOperations.ListBlobs(this.ContainerUrl, this.SasQueryString), enumerateCollection: true);
}
