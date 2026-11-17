using System;
using System.Diagnostics;
using System.IO;
using System.Management.Automation;
using System.Net.NetworkInformation; // Ping, PingReply, IPStatus
using System.Runtime.InteropServices;
using System.Security;
using System.Text;
using System.Threading;

namespace AMT.PowerShell.Common.Commands.Ensure;

/// <summary>Verify an internet connection is available, optionally connecting to a named Wi-Fi network.</summary>
/// <remarks>
/// Pings 8.8.8.8 to test reachability.
/// If no connection exists and <see cref="Name"/> is supplied, uses <c>netsh wlan</c> to add and connect
/// a WPA2-PSK (or open) profile, then polls for up to 60 seconds.
/// Outputs <see langword="true"/> when a connection was established by this invocation,
/// <see langword="false"/> when one was already present.
/// Throws a terminating ConnectionError if no network can be reached.
/// The Wi-Fi connect path is Windows-only.
/// </remarks>
/// <example>
/// <code>Invoke-EnsureNetwork</code>
/// Passes silently when already connected; throws if no network is available.
/// </example>
/// <example>
/// <code>Invoke-EnsureNetwork -Name 'Corp-WiFi' -Password $securePassword</code>
/// Attempts to connect to the Corp-WiFi SSID using the supplied password before asserting connectivity.
/// </example>
[Cmdlet("Invoke", "EnsureNetwork")]
[OutputType(typeof(bool))]
public sealed class InvokeEnsureNetworkCommand : PSCmdlet {
    // Retries mirror the legacy PS: 60 × 1 s = 60 s total wait.
    private const int MaxConnectRetries = 60;
    private const int RetryDelayMs = 1_000;

    // Seam: replaces TryPingInternet() for both the initial check and the polling loop.
    internal static Func<bool>? NetworkAvailableOverride { get; set; }

    // Seam: replaces Process.Start for netsh invocations; (exe, args) -> exitCode.
    // Injecting this also enables the connect path on non-Windows (for deterministic tests).
    internal static Func<string, string, int>? ProcessRunnerOverride { get; set; }

    // Seam: replaces Thread.Sleep in the polling loop; ms -> void.
    internal static Action<int>? DelayMsOverride { get; set; }

    // Legacy call-site compatibility: AutoSetup.ps1 passes -Name / -Password.
    /// <summary>SSID of the Wi-Fi network to connect to when internet is not already reachable.</summary>
    [Parameter]
    [AllowNull]
    [AllowEmptyString]
    public string? Name { get; set; }

    /// <summary>Pre-shared key for the Wi-Fi network; omit for open (unauthenticated) networks.</summary>
    [Parameter]
    [AllowNull]
    public SecureString? Password { get; set; }

    protected override void ProcessRecord() {
        if (IsNetworkAvailable()) {
            // Already connected; no setup performed.
            this.WriteObject(false);
            return;
        }

        // Cannot attempt connect without a profile name.
        if (string.IsNullOrEmpty(Name)) {
            ThrowNoNetwork();
            return;
        }

        // netsh is Windows-only; on other platforms allow only when the process runner
        // is injected (e.g. in tests).
        var canConnect = RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
            || ProcessRunnerOverride is not null;

        if (!canConnect || !TryConnect(Name!)) {
            ThrowNoNetwork();
            return;
        }

        this.WriteObject(true);
    }

    private bool TryConnect(string name) {
        string? plainPassword = null;
        if (Password != null) {
            plainPassword = SecureStringToString(Password);
        }

        var ssidHex = BuildSsidHex(name);
        var tempFile = Path.Combine(Path.GetTempPath(), $"AMT-{name}.xml");

        try {
            WriteWifiProfile(tempFile, name, ssidHex, plainPassword);

            RunNetsh($"wlan add profile filename=\"{tempFile}\"");
            RunNetsh($"wlan show profiles {name} key=clear");
            RunNetsh($"wlan connect name=\"{name}\"");
        } finally {
            try { File.Delete(tempFile); } catch { }
        }

        for (var i = 0; i < MaxConnectRetries; i++) {
            Delay(RetryDelayMs);
            if (IsNetworkAvailable()) {
                return true;
            }
        }

        return false;
    }

    private bool IsNetworkAvailable() =>
        NetworkAvailableOverride?.Invoke() ?? TryPingInternet();

    // Pings Google's public DNS (IP-literal, no DNS resolution needed) to confirm
    // internet reachability — matches legacy Test-Connection google.com semantics.
    private static bool TryPingInternet() {
        try {
            using var ping = new Ping();
            var reply = ping.Send("8.8.8.8", 2_000);
            return reply.Status == IPStatus.Success;
        } catch {
            return false;
        }
    }

    private void RunNetsh(string args) {
        if (ProcessRunnerOverride is not null) {
            ProcessRunnerOverride("netsh", args);
            return;
        }

        using var proc = Process.Start(new ProcessStartInfo {
            FileName = "netsh",
            Arguments = args,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        });
        proc?.WaitForExit(30_000);
    }

    private void Delay(int ms) {
        if (DelayMsOverride is not null) {
            DelayMsOverride(ms);
        } else {
            Thread.Sleep(ms);
        }
    }

    private void ThrowNoNetwork() =>
        this.ThrowTerminatingError(new ErrorRecord(
            new InvalidOperationException("No network connection is available."),
            "AMT.Ensure.NoNetwork",
            ErrorCategory.ConnectionError,
            null));

    private static string BuildSsidHex(string name) {
        var sb = new StringBuilder(name.Length * 2);
        foreach (var c in name) {
            sb.AppendFormat("{0:X2}", (int)c);
        }
        return sb.ToString();
    }

    private static void WriteWifiProfile(
            string path,
            string name,
            string ssidHex,
            string? plainPassword) {
        const string withPassword =
            "<?xml version=\"1.0\"?>" +
            "<WLANProfile xmlns=\"http://www.microsoft.com/networking/WLAN/profile/v1\">" +
            "<name>{0}</name>" +
            "<SSIDConfig><SSID><hex>{1}</hex><name>{0}</name></SSID></SSIDConfig>" +
            "<connectionType>ESS</connectionType><connectionMode>auto</connectionMode>" +
            "<MSM><security><authEncryption>" +
            "<authentication>WPA2PSK</authentication><encryption>AES</encryption>" +
            "<useOneX>false</useOneX></authEncryption>" +
            "<sharedKey><keyType>passPhrase</keyType><protected>false</protected>" +
            "<keyMaterial>{2}</keyMaterial></sharedKey>" +
            "</security></MSM></WLANProfile>";

        const string open =
            "<?xml version=\"1.0\"?>" +
            "<WLANProfile xmlns=\"http://www.microsoft.com/networking/WLAN/profile/v1\">" +
            "<name>{0}</name>" +
            "<SSIDConfig><SSID><hex>{1}</hex><name>{0}</name></SSID></SSIDConfig>" +
            "<connectionType>ESS</connectionType><connectionMode>auto</connectionMode>" +
            "</WLANProfile>";

        var xml = plainPassword != null
            ? string.Format(withPassword, name, ssidHex, plainPassword)
            : string.Format(open, name, ssidHex);

        File.WriteAllText(path, xml, Encoding.UTF8);
    }

    private static string SecureStringToString(SecureString ss) {
        var ptr = Marshal.SecureStringToGlobalAllocUnicode(ss);
        try {
            return Marshal.PtrToStringUni(ptr) ?? string.Empty;
        } finally {
            Marshal.ZeroFreeGlobalAllocUnicode(ptr);
        }
    }
}
