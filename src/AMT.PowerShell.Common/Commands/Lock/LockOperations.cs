using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;

namespace AMT.PowerShell.Common.Commands.Lock;

internal static class LockOperations {
    private const int TimeoutSeconds = 600;
    private const int RetryMilliseconds = 1000;

    internal static string BuildLockPath(string? scriptName, string resourceId) {
        var sanitizedScript = Sanitize(scriptName);
        var sanitizedResource = Sanitize(resourceId);

        return Path.Combine(Path.GetTempPath(), $"AMT_{sanitizedScript}_{sanitizedResource}.lock");
    }

    internal static string ResolveCallerScriptName(string? scriptNameFromParameter, string? invocationScriptName, string? invocationCommandName) {
        if (!string.IsNullOrWhiteSpace(scriptNameFromParameter)) {
            return Path.GetFileNameWithoutExtension(scriptNameFromParameter);
        }

        if (!string.IsNullOrWhiteSpace(invocationScriptName)) {
            return Path.GetFileNameWithoutExtension(invocationScriptName);
        }

        if (!string.IsNullOrWhiteSpace(invocationCommandName)) {
            return Path.GetFileNameWithoutExtension(invocationCommandName);
        }

        return "AMT";
    }

    internal static FileStream WaitForLock(string lockPath, string? lockOwner) {
        var started = Stopwatch.StartNew();
        var lockDirectory = Path.GetDirectoryName(lockPath);

        if (!string.IsNullOrWhiteSpace(lockDirectory)) {
            Directory.CreateDirectory(lockDirectory);
        }

        while (true) {
            try {
                var handle = new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
                WriteMetadata(handle, lockOwner);
                return handle;
            } catch (IOException exception) {
                if (!ShouldRetryLockAcquisition(exception)) {
                    throw;
                }

                if (started.Elapsed.TotalSeconds >= TimeoutSeconds) {
                    throw new TimeoutException($"Timed out waiting for lock file '{lockPath}' after {TimeoutSeconds}s.");
                }

                Thread.Sleep(RetryMilliseconds);
            }
        }
    }

    internal static bool ShouldRetryLockAcquisition(IOException exception) {
        if (exception.GetType() != typeof(IOException)) {
            return false;
        }

        var errorCode = exception.HResult & 0xFFFF;
        if (errorCode is 32 or 33) {
            return true;
        }

        if (exception.HResult is 11 or 35 || errorCode is 11 or 35) {
            return true;
        }

        var message = exception.Message;
        return message.IndexOf("used by another process", StringComparison.OrdinalIgnoreCase) >= 0
            || message.IndexOf("sharing violation", StringComparison.OrdinalIgnoreCase) >= 0
            || message.IndexOf("lock", StringComparison.OrdinalIgnoreCase) >= 0;
    }

    internal static void ReleaseLock(IDisposable? lockHandle, string? lockPath) {
        if (lockHandle is not null) {
            try {
                lockHandle.Dispose();
            } catch {
            }
        }

        if (string.IsNullOrWhiteSpace(lockPath)) {
            return;
        }

        try {
            if (File.Exists(lockPath)) {
                File.Delete(lockPath);
            }
        } catch {
        }
    }

    private static string Sanitize(string? value) {
        if (string.IsNullOrEmpty(value)) {
            return string.Empty;
        }

        var source = value!;
        var builder = new StringBuilder(source.Length);
        foreach (var character in source) {
            if (char.IsLetterOrDigit(character)) {
                builder.Append(character);
            }
        }

        return builder.ToString();
    }

    private static void WriteMetadata(FileStream handle, string? lockOwner) {
        handle.SetLength(0);

        var metadata = new StringBuilder();
        metadata.Append("PID=");
        metadata.Append(Process.GetCurrentProcess().Id.ToString(CultureInfo.InvariantCulture));

        if (!string.IsNullOrWhiteSpace(lockOwner)) {
            metadata.Append('\n');
            metadata.Append("Owner=");
            metadata.Append(lockOwner);
        }

        metadata.Append('\n');
        metadata.Append("Started=");
        metadata.Append(DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture));

        var bytes = Encoding.UTF8.GetBytes(metadata.ToString());
        handle.Write(bytes, 0, bytes.Length);
        handle.Flush();
    }
}
