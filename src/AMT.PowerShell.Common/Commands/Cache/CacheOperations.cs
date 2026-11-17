// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.IO;

namespace AMT.PowerShell.Common.Commands.Cache;

internal static class CacheOperations {
    // Override the cache folder for test isolation.
    internal static string? CacheFolderOverride { get; set; }

    private static string GetCacheFolder() =>
        CacheFolderOverride ?? Path.Combine(Path.GetTempPath(), "PSCache");

    internal static string GetCachePath(string name) =>
        Path.Combine(GetCacheFolder(), $"Cached-{name}");

    internal static void EnsureCacheFolder(string cachePath) {
        var folder = Path.GetDirectoryName(cachePath);
        if (!string.IsNullOrWhiteSpace(folder)) {
            Directory.CreateDirectory(folder);
        }
    }
}
