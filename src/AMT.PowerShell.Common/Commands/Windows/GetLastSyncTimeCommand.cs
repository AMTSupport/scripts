using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Management.Automation;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace AMT.PowerShell.Common.Commands.Windows;

/// <summary>Gets the timestamp of the last successful W32TM time synchronisation.</summary>
/// <remarks>
/// Calls <c>w32tm /query /status</c> and parses the "Last Successful Sync Time" field.
/// Returns the Unix epoch (1970-01-01) when the query fails or no sync time is found.
/// Windows-only; requires the w32tm service to be running.
/// </remarks>
/// <example>
/// <code>Get-LastSyncTime</code>
/// Returns the DateTime of the last successful Windows time synchronisation.
/// </example>
[Cmdlet(VerbsCommon.Get, "LastSyncTime")]
[OutputType(typeof(DateTime))]
public sealed class GetLastSyncTimeCommand : PSCmdlet {
    private const string LastSyncTimePattern = "^\\s*Last Successful Sync Time:\\s*(?<DateTime>.+?)\\s*$";
    private const string W32tmExecutable = "w32tm";

    private static readonly DateTime UnixEpoch = new DateTime(1970, 1, 1);

    protected override void ProcessRecord() => this.WriteObject(GetLastSyncTime());

    internal static DateTime GetLastSyncTime() {
        if (!TryRunW32tm("/query /status", out var output)) {
            return UnixEpoch;
        }

        return ParseLastSyncTime(output);
    }

    internal static bool TryResyncTime() => TryRunW32tm("/resync /force", out _);

    internal static DateTime ParseLastSyncTime(string output) {
        if (string.IsNullOrWhiteSpace(output)) {
            return UnixEpoch;
        }

        var match = Regex.Match(output, LastSyncTimePattern, RegexOptions.Multiline | RegexOptions.CultureInvariant);
        if (!match.Success) {
            return UnixEpoch;
        }

        var syncTime = match.Groups["DateTime"].Value.Trim();
        if (DateTime.TryParse(syncTime, CultureInfo.CurrentCulture, DateTimeStyles.AllowWhiteSpaces, out var parsed)) {
            return parsed;
        }

        if (DateTime.TryParse(syncTime, CultureInfo.InvariantCulture, DateTimeStyles.AllowWhiteSpaces, out parsed)) {
            return parsed;
        }

        return UnixEpoch;
    }

    private static bool TryRunW32tm(string arguments, out string output) {
        output = string.Empty;

        try {
            using var process = Process.Start(new ProcessStartInfo {
                FileName = W32tmExecutable,
                Arguments = arguments,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            });

            if (process is null) {
                return false;
            }

            var standardOutputTask = process.StandardOutput.ReadToEndAsync();
            var standardErrorTask = process.StandardError.ReadToEndAsync();
            process.WaitForExit();
            Task.WaitAll(standardOutputTask, standardErrorTask);

            output = string.Concat(standardOutputTask.Result, Environment.NewLine, standardErrorTask.Result);
            return process.ExitCode == 0;
        } catch (Exception ex) when (ex is Win32Exception or InvalidOperationException or NotSupportedException) {
            return false;
        }
    }
}
