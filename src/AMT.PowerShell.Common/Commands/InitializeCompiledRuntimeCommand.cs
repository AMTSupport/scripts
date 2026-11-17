using System;
using System.Collections;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Management.Automation;
using System.Reflection;
using System.Text;
using System.Threading;
using AMT.PowerShell.Common.Module;

namespace AMT.PowerShell.Common.Commands;

/// <summary>Extracts embedded modules and prepares a private PSModulePath for a compiled script runtime.</summary>
/// <remarks>
/// Iterates the EmbeddedModules descriptors produced by the AMT compiler, extracts each into a
/// content-addressed folder under the private module root, and prepends that root to PSModulePath.
/// Returns a RuntimeState object describing the original and updated module paths.
/// Intended for use by compiled script templates; not for interactive use.
/// </remarks>
/// <example>
/// <code>Initialize-AMTCompiledRuntime -EmbeddedModules $embeddedModules</code>
/// Extracts the embedded modules into the default private root and updates PSModulePath.
/// </example>
[Cmdlet(VerbsData.Initialize, "AMTCompiledRuntime")]
[OutputType(typeof(RuntimeState))]
public sealed class InitializeCompiledRuntimeCommand : Cmdlet {
    private const string Base64Utf8ContentType = "Base64Utf8";
    private const string ZipContentType = "Zip";
    private const string ReadyMarkerName = ".ready";
    private const string LockMarkerName = ".lock";
    private const string ModuleFolderNameSuffix = "-";
    private const int LockRetryDelayMilliseconds = 50;
    private const int LockTimeoutMilliseconds = 15000;

    /// <summary>Hashtable array of embedded module descriptors produced by the AMT compiler.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public Hashtable[] EmbeddedModules { get; set; } = [];

    /// <summary>Override for the private module extraction root; uses a system-default path when omitted.</summary>
    [Parameter]
    public string? PrivateModuleRoot { get; set; }

    protected override void ProcessRecord() {
        var originalModulePath = Environment.GetEnvironmentVariable("PSModulePath") ?? string.Empty;
        var psMajorVersion = GetPowerShellMajorVersion();
        var moduleRoot = string.IsNullOrWhiteSpace(this.PrivateModuleRoot)
            ? GetDefaultModuleRoot(psMajorVersion)
            : this.PrivateModuleRoot!;

        Directory.CreateDirectory(moduleRoot);

        var privatePsModulePath = PrependModulePath(originalModulePath, moduleRoot);
        Environment.SetEnvironmentVariable("PSModulePath", privatePsModulePath);

        var transientScriptPath = string.Empty;
        var scriptPath = string.Empty;

        foreach (var embeddedModule in this.EmbeddedModules) {
            if (embeddedModule is null) {
                continue;
            }

            var name = GetString(embeddedModule, "Name");
            var hash = GetString(embeddedModule, "Hash");
            var contentType = GetString(embeddedModule, "Type");
            var content = GetString(embeddedModule, "Content");

            if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(hash) || string.IsNullOrWhiteSpace(contentType)) {
                continue;
            }

            var moduleFolderName = GetModuleFolderName(name, hash);
            var moduleFolder = Path.Combine(moduleRoot, moduleFolderName);

            if (string.Equals(contentType, Base64Utf8ContentType, StringComparison.OrdinalIgnoreCase)) {
                var decoded = Convert.FromBase64String(content ?? string.Empty);
                var text = DecodeText(decoded, psMajorVersion);

                if (string.IsNullOrEmpty(scriptPath)) {
                    transientScriptPath = Path.Combine(Path.GetTempPath(), $"{moduleFolderName}-{Guid.NewGuid():N}.ps1");
                    scriptPath = transientScriptPath;
                    WriteTextFile(transientScriptPath, text, psMajorVersion);
                    continue;
                }

                Directory.CreateDirectory(moduleFolder);
                var modulePath = Path.Combine(moduleFolder, $"{moduleFolderName}.psm1");
                using var lockHandle = AcquireModuleLock(moduleFolder, modulePath, psMajorVersion);
                if (lockHandle.ShouldSkip) {
                    continue;
                }

                WriteTextFile(modulePath, text, psMajorVersion);
                WriteReadyMarker(moduleFolder, psMajorVersion);
                continue;
            }

            if (string.Equals(contentType, ZipContentType, StringComparison.OrdinalIgnoreCase)) {
                Directory.CreateDirectory(moduleFolder);
                var archiveBytes = Convert.FromBase64String(content ?? string.Empty);
                var archivePath = Path.Combine(moduleFolder, $"{moduleFolderName}.zip");
                using var lockHandle = AcquireModuleLock(moduleFolder, archivePath, psMajorVersion);
                if (lockHandle.ShouldSkip) {
                    TryDeleteFile(archivePath);
                    continue;
                }

                try {
                    File.WriteAllBytes(archivePath, archiveBytes);
                    ZipFile.ExtractToDirectory(archivePath, moduleFolder);
                    WriteReadyMarker(moduleFolder, psMajorVersion);
                } finally {
                    TryDeleteFile(archivePath);
                }
            }
        }

        this.WriteObject(new RuntimeState(
            originalModulePath,
            privatePsModulePath,
            scriptPath,
            transientScriptPath));
    }

    private static string GetDefaultModuleRoot(int psMajorVersion) {
        var commonAppData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        if (string.IsNullOrWhiteSpace(commonAppData)) {
            commonAppData = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".local",
                "share");
        }
        return Path.Combine(commonAppData, "AMT", "PowerShell", "Modules", $"PS{psMajorVersion}");
    }

    private static int GetPowerShellMajorVersion() {
        var psVersionInfoType = Type.GetType("System.Management.Automation.PSVersionInfo, System.Management.Automation", throwOnError: false);
        var psVersionProperty = psVersionInfoType?.GetProperty("PSVersion", BindingFlags.Public | BindingFlags.Static);
        var psVersion = psVersionProperty?.GetValue(null) as Version;
        var powerShellMajor = psVersion?.Major ?? 0;

        return powerShellMajor > 0 ? powerShellMajor : 5;
    }

    private static string PrependModulePath(string original, string privateRoot) {
        if (string.IsNullOrWhiteSpace(original)) {
            return privateRoot;
        }

        var parts = original.Split(Path.PathSeparator)
            .Where(part => !string.IsNullOrWhiteSpace(part))
            .ToList();

        if (parts.Any(part => string.Equals(part, privateRoot, StringComparison.OrdinalIgnoreCase))) {
            return original;
        }

        parts.Insert(0, privateRoot);
        return string.Join(Path.PathSeparator.ToString(CultureInfo.InvariantCulture), parts);
    }

    private static string GetModuleFolderName(string name, string hash) => $"{name}{ModuleFolderNameSuffix}{hash}";

    private static string GetString(Hashtable table, string key) => table[key]?.ToString() ?? string.Empty;

    private static string DecodeText(byte[] bytes, int psMajorVersion) {
        var encoding = psMajorVersion < 6
            ? new UTF8Encoding(encoderShouldEmitUTF8Identifier: true)
            : new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);
        return encoding.GetString(bytes);
    }

    private static void WriteTextFile(string path, string content, int psMajorVersion) {
        var encoding = psMajorVersion < 6
            ? new UTF8Encoding(encoderShouldEmitUTF8Identifier: true)
            : new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);
        File.WriteAllText(path, content, encoding);
    }

    private static ModuleLockResult AcquireModuleLock(string moduleFolder, string payloadPath, int psMajorVersion) {
        var lockPath = Path.Combine(moduleFolder, LockMarkerName);
        var started = Environment.TickCount;

        while (true) {
            if (IsModuleReady(moduleFolder)) {
                return ModuleLockResult.Skip;
            }

            try {
                var stream = new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
                WriteLockMarker(stream, psMajorVersion);
                return new ModuleLockResult(stream, lockPath, shouldSkip: false);
            } catch (IOException) {
                if (Environment.TickCount - started >= LockTimeoutMilliseconds) {
                    throw new TimeoutException($"Timed out waiting for module lock '{lockPath}'. Payload '{payloadPath}' not ready.");
                }

                Thread.Sleep(LockRetryDelayMilliseconds);
            }
        }
    }

    private static bool IsModuleReady(string moduleFolder) {
        var readyPath = Path.Combine(moduleFolder, ReadyMarkerName);
        return File.Exists(readyPath) && HasExtractedContent(moduleFolder, readyPath);
    }

    private static bool HasExtractedContent(string moduleFolder, string readyPath) => Directory.EnumerateFileSystemEntries(moduleFolder)
            .Any(path => !string.Equals(path, readyPath, StringComparison.OrdinalIgnoreCase) && !string.Equals(path, Path.Combine(moduleFolder, LockMarkerName), StringComparison.OrdinalIgnoreCase));

    private static void WriteReadyMarker(string moduleFolder, int psMajorVersion) {
        var readyPath = Path.Combine(moduleFolder, ReadyMarkerName);
        WriteTextFile(readyPath, DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture), psMajorVersion);
    }

    private static void WriteLockMarker(FileStream stream, int psMajorVersion) {
        stream.SetLength(0);
        var bytes = GetMarkerBytes(DateTimeOffset.UtcNow.ToString("O", CultureInfo.InvariantCulture), psMajorVersion);
        stream.Write(bytes, 0, bytes.Length);
        stream.Flush(true);
    }

    private static byte[] GetMarkerBytes(string content, int psMajorVersion) => (psMajorVersion < 6
            ? new UTF8Encoding(encoderShouldEmitUTF8Identifier: true)
            : new UTF8Encoding(encoderShouldEmitUTF8Identifier: false)).GetBytes(content);

    private static void TryDeleteFile(string path) {
        try {
            if (File.Exists(path)) {
                File.Delete(path);
            }
        } catch {
        }
    }

    private sealed class ModuleLockResult(FileStream? stream, string? lockPath, bool shouldSkip) : IDisposable {
        private readonly FileStream? Stream = stream;
        private readonly string? LockPath = lockPath;
        private bool Disposed;

        public bool ShouldSkip { get; } = shouldSkip;

        public static ModuleLockResult Skip { get; } = new ModuleLockResult(null, null, shouldSkip: true);

        public void Dispose() {
            if (this.Disposed) return;

            this.Disposed = true;
            this.Stream?.Dispose();
            if (!string.IsNullOrWhiteSpace(this.LockPath)) {
                TryDeleteFile(this.LockPath!);
            }
        }
    }
}
