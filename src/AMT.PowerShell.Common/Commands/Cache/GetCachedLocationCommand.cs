// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.IO;
using System.Management.Automation;
using System.Text;

namespace AMT.PowerShell.Common.Commands.Cache;

/// <summary>Resolve the filesystem path of a named cache file, invoking <c>CreateBlock</c> to populate it when missing or stale.</summary>
/// <remarks>
/// <para>Derives the cache file path from <c>Name</c> using <see cref="CacheOperations.GetCachePath"/>
/// and validates the existing file against <c>MaxAge</c>, <c>IsValidBlock</c>, or <c>NoCache</c>.
/// When the file is absent or invalid it is recreated by calling <c>CreateBlock</c>.</para>
/// <para>Content is written as plain text via <see cref="System.IO.File.WriteAllText"/> unless
/// <c>WriteBlock</c> is supplied, which receives the cache path and raw content object as arguments.</para>
/// <para>The resolved cache file path is emitted to the pipeline regardless of whether the file
/// was freshly created or already existed.</para>
/// </remarks>
/// <example>
/// <code>Get-CachedLocation -Name 'wallpaper' -CreateBlock { Download-Blob } -WriteBlock { param($p,$c) [IO.File]::WriteAllBytes($p,$c) }</code>
/// Returns the path to the cached file, downloading the blob only when needed.
/// </example>
[Cmdlet(VerbsCommon.Get, "CachedLocation")]
[OutputType(typeof(string))]
public sealed class GetCachedLocationCommand : PSCmdlet {
    /// <summary>Unique name that identifies the cache entry and is used to derive the cache file path.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string Name { get; set; } = string.Empty;

    /// <summary>Script block invoked to generate content when the cache is missing or stale.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNull]
    public ScriptBlock CreateBlock { get; set; } = null!;

    /// <summary>Maximum age of the cache file; when exceeded the file is deleted and recreated via <c>CreateBlock</c>.</summary>
    [Parameter]
    public TimeSpan MaxAge { get; set; }

    /// <summary>Optional script block receiving the cache file path and returning a boolean indicating whether the content is still valid.</summary>
    [Parameter]
    public ScriptBlock? IsValidBlock { get; set; }

    /// <summary>Optional script block to write content to the cache file; receives the cache path and raw content object as arguments.</summary>
    [Parameter]
    public ScriptBlock? WriteBlock { get; set; }

    /// <summary>When present, bypasses any existing cache and always invokes <c>CreateBlock</c> to regenerate content.</summary>
    [Parameter]
    public SwitchParameter NoCache { get; set; }

    protected override void ProcessRecord() {
        var cachePath = CacheOperations.GetCachePath(Name);
        CacheOperations.EnsureCacheFolder(cachePath);

        if (File.Exists(cachePath)) {
            var shouldDelete = false;

            if (NoCache.IsPresent) {
                shouldDelete = true;
            } else if (MyInvocation.BoundParameters.ContainsKey(nameof(MaxAge))) {
                var age = DateTime.UtcNow - File.GetLastWriteTimeUtc(cachePath);
                if (age > MaxAge) shouldDelete = true;
            } else if (IsValidBlock is not null) {
                var validResult = IsValidBlock.Invoke(cachePath);
                var isValid = validResult.Count > 0 && validResult[0].BaseObject is bool b && b;
                if (!isValid) shouldDelete = true;
            }

            if (shouldDelete) File.Delete(cachePath);
        }

        if (!File.Exists(cachePath)) {
            var contentResults = CreateBlock.Invoke();

            if (WriteBlock is not null) {
                // Preserve raw types from CreateBlock (e.g. byte[]) without string coercion.
                // PS enumerates arrays through the pipeline, so collect all items as an array
                // when there is more than one (e.g. each byte of a Byte[] comes back separately).
                object rawContent;
                if (contentResults.Count == 0) {
                    rawContent = Array.Empty<object>();
                } else if (contentResults.Count == 1) {
                    rawContent = contentResults[0].BaseObject ?? string.Empty;
                } else {
                    var items = new object[contentResults.Count];
                    for (var i = 0; i < contentResults.Count; i++) {
                        items[i] = contentResults[i].BaseObject ?? string.Empty;
                    }
                    rawContent = items;
                }

                WriteBlock.Invoke(cachePath, rawContent);
            } else {
                var content = contentResults.Count > 0
                    ? contentResults[0].BaseObject?.ToString() ?? string.Empty
                    : string.Empty;
                File.WriteAllText(cachePath, content, Encoding.UTF8);
            }
        }

        WriteObject(cachePath);
    }
}
