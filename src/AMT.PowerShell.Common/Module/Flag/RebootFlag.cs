namespace AMT.PowerShell.Common.Module;

using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security;

public sealed class RebootFlag : Flag {
    private const string LinuxUptimePath = "/proc/uptime";

    internal const string TickCount32FallbackWrapNote = "TickCount fallback wraps every ~49.7 days and cannot distinguish post-wrap uptime from a fresh boot.";

    internal static Func<bool>? LinuxUptimeFileExistsOverride { get; set; }

    internal static Func<string>? LinuxUptimeReaderOverride { get; set; }

    internal static Func<long>? TickCount64ProviderOverride { get; set; }

    internal static Func<int>? TickCountProviderOverride { get; set; }

    internal static Func<DateTimeOffset>? UtcNowProviderOverride { get; set; }

    private static readonly Func<bool> DefaultLinuxUptimeFileExists = () => File.Exists(LinuxUptimePath);

    private static readonly Func<string> DefaultLinuxUptimeReader = () => File.ReadAllText(LinuxUptimePath);

    private static readonly Func<long> DefaultTickCount64Provider = ResolveTickCount64ViaReflection;

    private static readonly Func<int> DefaultTickCountProvider = () => Environment.TickCount;

    private static readonly Func<DateTimeOffset> DefaultUtcNowProvider = () => DateTimeOffset.UtcNow;

    public RebootFlag() : base("reboot") {
    }

    public bool Required() {
        if (!this.Exists()) {
            return false;
        }

        var bootTimeUtc = ResolveBootTimeUtc();
        if (bootTimeUtc is null) {
            return true;
        }

        var flagWriteTimeUtc = File.GetLastWriteTimeUtc(this.FlagPath);
        return flagWriteTimeUtc > bootTimeUtc.Value.UtcDateTime;
    }

    internal static DateTimeOffset? ResolveBootTimeUtc() {
        var linuxBootTimeUtc = TryGetLinuxBootTimeUtc();
        if (linuxBootTimeUtc is not null) {
            return linuxBootTimeUtc;
        }

        return TryGetTickCountBootTimeUtc();
    }

    private static DateTimeOffset? TryGetTickCountBootTimeUtc() {
        var utcNow = UtcNow();

        try {
            var uptimeMilliseconds64 = TickCount64Provider();
            if (uptimeMilliseconds64 < 0) {
                return null;
            }

            return utcNow - TimeSpan.FromMilliseconds(uptimeMilliseconds64);
        } catch (MissingMemberException) {
            // Runtime lacks TickCount64.
            // Fall back to TickCount and keep best-effort behaviour.
        } catch (TargetInvocationException) {
            return null;
        } catch (TargetException) {
            return null;
        } catch (MethodAccessException) {
            return null;
        } catch (MemberAccessException) {
            return null;
        } catch (AmbiguousMatchException) {
            return null;
        } catch (InvalidCastException) {
            return null;
        } catch (NotSupportedException) {
            return null;
        } catch (ArgumentOutOfRangeException) {
            return null;
        } catch (OverflowException) {
            return null;
        }

        try {
            var tickCount = TickCountProvider();
            var uptimeMilliseconds32 = unchecked((uint)tickCount);

            // TickCount fallback wraps at ~49.7 days.
            // Post-wrap uptime cannot be distinguished from fresh boot.
            _ = TickCount32FallbackWrapNote;

            return utcNow - TimeSpan.FromMilliseconds(uptimeMilliseconds32);
        } catch (ArgumentOutOfRangeException) {
            return null;
        } catch (OverflowException) {
            return null;
        }
    }

    private static DateTimeOffset? TryGetLinuxBootTimeUtc() {
        if (!LinuxUptimeFileExists()) {
            return null;
        }

        try {
            var uptimeText = LinuxUptimeReader()
                .Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries)
                .FirstOrDefault();

            if (!double.TryParse(uptimeText, NumberStyles.Float, CultureInfo.InvariantCulture, out var uptimeSeconds)) {
                return null;
            }

            return UtcNow() - TimeSpan.FromSeconds(uptimeSeconds);
        } catch (IOException) {
            return null;
        } catch (UnauthorizedAccessException) {
            return null;
        } catch (SecurityException) {
            return null;
        } catch (NotSupportedException) {
            return null;
        } catch (ArgumentOutOfRangeException) {
            return null;
        } catch (ArgumentException) {
            return null;
        } catch (OverflowException) {
            return null;
        }
    }

    private static bool LinuxUptimeFileExists() => (LinuxUptimeFileExistsOverride ?? DefaultLinuxUptimeFileExists).Invoke();

    private static string LinuxUptimeReader() => (LinuxUptimeReaderOverride ?? DefaultLinuxUptimeReader).Invoke();

    private static long TickCount64Provider() => (TickCount64ProviderOverride ?? DefaultTickCount64Provider).Invoke();

    private static int TickCountProvider() => (TickCountProviderOverride ?? DefaultTickCountProvider).Invoke();

    private static DateTimeOffset UtcNow() => (UtcNowProviderOverride ?? DefaultUtcNowProvider).Invoke();

    private static long ResolveTickCount64ViaReflection() {
        var tickCount64Property = typeof(Environment).GetProperty("TickCount64", BindingFlags.Public | BindingFlags.Static);
        if (tickCount64Property is null) {
            throw new MissingMemberException(typeof(Environment).FullName, "TickCount64");
        }

        var value = tickCount64Property.GetValue(null, null);
        if (value is long tickCount64) {
            return tickCount64;
        }

        throw new InvalidCastException("Environment.TickCount64 value was not Int64.");
    }
}
