using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace AMT.PowerShell.Common.Commands.Registry;

/// <summary>Runs a script block against each local user's registry hive.</summary>
/// <remarks>
/// Enumerates all user profiles under HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList
/// (filtering to standard and AzureAD SIDs). For each profile, temporarily loads the
/// <c>ntuser.dat</c> hive via <c>reg.exe</c> if it is not already mounted, invokes the script block,
/// then unloads the hive if it was loaded by this cmdlet.
/// The script block receives a PSObject with <c>SID</c>, <c>UserHive</c>, and <c>Username</c> properties.
/// Only supported on Windows.
/// </remarks>
/// <example>
/// <code>
/// Invoke-OnEachUserHive -ScriptBlock {
///     param($hive)
///     Set-RegistryKey -Path "Registry::HKEY_USERS\$($hive.SID)\SOFTWARE\MyApp" -Key 'Setting' -Value '1' -Kind DWord
/// }
/// </code>
/// Writes a DWord registry value to every loaded user hive.
/// </example>
[Cmdlet("Invoke", "OnEachUserHive")]
public sealed class InvokeOnEachUserHiveCommand : PSCmdlet {
    // Generous timeouts: hive files can be large; unload is typically faster.
    private const int HiveLoadTimeoutMs = 30_000;
    private const int HiveUnloadTimeoutMs = 15_000;

    // Seams for deterministic tests: override replaces the reg.exe process call.
    // Signature mirrors the real method: (sid, hivePath) → success.
    internal static Func<string, string, bool>? HiveLoaderOverride { get; set; }
    // Signature: (sid) → success.
    internal static Func<string, bool>? HiveUnloaderOverride { get; set; }

    private const string ProfileListPath =
        @"HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList";

    // Matches standard Windows local-account and AzureAD SIDs.
    private static readonly Regex SidPattern = new(
        @"^(?:S-1-5-21|S-1-12-1)-\d+-\d+-\d+-\d+$",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    /// <summary>
    /// Script block to execute for each user profile;
    /// receives a PSObject with <c>SID</c>, <c>UserHive</c>, and <c>Username</c>.
    /// </summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNull]
    public ScriptBlock ScriptBlock { get; set; } = null!;

    protected override void ProcessRecord() {
        if (!RegistryHelper.IsRegistrySupported) {
            RegistryHelper.WriteUnsupportedError(this);
            return;
        }

        var profiles = GetUserProfiles();
        var loadedSids = GetLoadedSids();

        foreach (var profile in profiles) {
            var wasLoaded = loadedSids.Contains(profile.Sid);
            var loadedByUs = false;

            if (!wasLoaded) {
                loadedByUs = TryLoadHive(profile.Sid, profile.UserHive);
                if (!loadedByUs) {
                    this.WriteWarning($"Failed to load user hive for SID '{profile.Sid}'; skipping.");
                    continue;
                }
            }

            try {
                var hiveObject = BuildHiveObject(profile);
                foreach (var result in this.ScriptBlock.Invoke(hiveObject)) {
                    this.WriteObject(result);
                }
            } finally {
                if (loadedByUs) {
                    // Release registry handles before unloading.
                    GC.Collect();
                    GC.WaitForPendingFinalizers();
                    if (!TryUnloadHive(profile.Sid)) {
                        this.WriteWarning(
                            $"Failed to unload user hive for SID '{profile.Sid}'; the hive may remain loaded.");
                    }
                }
            }
        }
    }

    private IReadOnlyList<UserProfile> GetUserProfiles() {
        var profiles = new List<UserProfile>();

        if (!this.InvokeProvider.Item.Exists(ProfileListPath)) {
            return profiles;
        }

        // PowerShellStandard ChildItem.Get uses string (not string[]) as first argument.
        var children = this.InvokeProvider.ChildItem.Get(ProfileListPath, recurse: false);

        foreach (var sidItem in children) {
            var sid = sidItem.Properties["PSChildName"]?.Value as string;
            if (string.IsNullOrEmpty(sid) || !SidPattern.IsMatch(sid!)) {
                continue;
            }

            var sidPath = $"{ProfileListPath}\\{sid}";
            string? profilePath = null;

            try {
                var props = this.InvokeProvider.Property.Get(
                    sidPath,
                    new System.Collections.ObjectModel.Collection<string> { "ProfileImagePath" });
                profilePath = props.Count > 0
                    ? props[0].Properties["ProfileImagePath"]?.Value as string
                    : null;
            } catch {
                continue;
            }

            if (string.IsNullOrEmpty(profilePath)) {
                continue;
            }

            var hivePath = Path.Combine(profilePath!, "ntuser.dat");
            if (!File.Exists(hivePath)) {
                continue;
            }

            var username = Path.GetFileName(
                profilePath!.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));

            profiles.Add(new UserProfile(sid!, hivePath, username));
        }

        return profiles;
    }

    private IReadOnlyCollection<string> GetLoadedSids() {
        var loaded = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        try {
            // PowerShellStandard ChildItem.Get uses string (not string[]) as first argument.
            var children = this.InvokeProvider.ChildItem.Get("Registry::HKEY_USERS", recurse: false);

            foreach (var item in children) {
                var name = item.Properties["PSChildName"]?.Value as string;
                if (!string.IsNullOrEmpty(name) && SidPattern.IsMatch(name!)) {
                    loaded.Add(name!);
                }
            }
        } catch {
            // If HKEY_USERS cannot be enumerated, treat all hives as unloaded.
        }

        return loaded;
    }

    private static bool TryLoadHive(string sid, string hivePath) {
        if (HiveLoaderOverride is not null) {
            return HiveLoaderOverride(sid, hivePath);
        }

        try {
            using var proc = Process.Start(new ProcessStartInfo {
                FileName = "reg",
                Arguments = $"load \"HKU\\{sid}\" \"{hivePath}\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            });

            if (proc is null) {
                return false;
            }

            if (!proc.WaitForExit(HiveLoadTimeoutMs)) {
                try { proc.Kill(); } catch { }
                return false;
            }

            return proc.ExitCode == 0;
        } catch {
            return false;
        }
    }

    // Returns true when reg.exe unloaded successfully within the timeout.
    private static bool TryUnloadHive(string sid) {
        if (HiveUnloaderOverride is not null) {
            return HiveUnloaderOverride(sid);
        }

        try {
            using var proc = Process.Start(new ProcessStartInfo {
                FileName = "reg",
                Arguments = $"unload \"HKU\\{sid}\"",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            });

            if (proc is null) {
                return false;
            }

            if (!proc.WaitForExit(HiveUnloadTimeoutMs)) {
                try { proc.Kill(); } catch { }
                return false;
            }

            return proc.ExitCode == 0;
        } catch {
            return false;
        }
    }

    private static PSObject BuildHiveObject(UserProfile profile) {
        var obj = new PSObject();
        obj.Properties.Add(new PSNoteProperty("SID", profile.Sid));
        obj.Properties.Add(new PSNoteProperty("UserHive", profile.UserHive));
        obj.Properties.Add(new PSNoteProperty("Username", profile.Username));
        return obj;
    }

    // Plain class avoids IsExternalInit requirement on netstandard2.0.
    private sealed class UserProfile {
        public string Sid { get; }
        public string UserHive { get; }
        public string Username { get; }

        public UserProfile(string sid, string userHive, string username) {
            Sid = sid;
            UserHive = userHive;
            Username = username;
        }
    }
}
