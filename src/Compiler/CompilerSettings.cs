// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.IO.Compression;

namespace Compiler;

internal enum EmbeddedLocalTextCompression {
    None,
    GZip
}

internal static class CompilerSettings {
    internal static EmbeddedLocalTextCompression EmbeddedLocalTextCompression { get; set; } = EmbeddedLocalTextCompression.GZip;

    internal static CompressionLevel EmbeddedLocalTextCompressionLevel { get; set; } = CompressionLevel.Optimal;

    internal static void ConfigureEmbeddedLocalTextCompression(string mode) {
        switch (mode.ToLowerInvariant()) {
            case "none":
                EmbeddedLocalTextCompression = EmbeddedLocalTextCompression.None;
                EmbeddedLocalTextCompressionLevel = CompressionLevel.NoCompression;
                break;
            case "gzip":
                EmbeddedLocalTextCompression = EmbeddedLocalTextCompression.GZip;
                EmbeddedLocalTextCompressionLevel = CompressionLevel.Optimal;
                break;
            default:
                throw new ArgumentException($"Unsupported embedded compression mode '{mode}'. Use none or gzip.");
        }
    }
}
