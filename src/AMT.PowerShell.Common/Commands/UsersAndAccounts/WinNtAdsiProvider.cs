// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.InteropServices;

namespace AMT.PowerShell.Common.Commands.UsersAndAccounts;

/// <summary>
/// Real ADSI backend backed by System.DirectoryServices.
/// Loaded reflectively so the netstandard2.0 module still compiles on non-Windows
/// hosts where the assembly is not a compile-time reference.
/// </summary>
internal sealed class WinNtAdsiProvider : IAdsiProvider {
    private const string WinNtPrefix = "WinNT://";

    private static readonly Lazy<Type?> DirectoryEntryType = new(LoadDirectoryEntryType);

    private static readonly Lazy<Type?> ManagementObjectSearcherType = new(LoadManagementObjectSearcherType);

    public bool IsSupported =>
        RuntimeInformation.IsOSPlatform(OSPlatform.Windows) && DirectoryEntryType.Value is not null;

    public IReadOnlyList<AdsiPrincipal> GetGroups() =>
        EnumerateChildren(CreateEntry(WinNtPrefix + ComputerName), "Group");

    public AdsiPrincipal GetGroup(string name) {
        try {
            return ToPrincipal(CreateEntry($"{WinNtPrefix}{ComputerName}/{name},group"));
        } catch (PlatformNotSupportedException) {
            throw;
        } catch (Exception) {
            throw new AdsiResolutionException($"Group '{name}' was not found.", name);
        }
    }

    public IReadOnlyList<AdsiPrincipal> GetUsers() =>
        EnumerateChildren(CreateEntry(WinNtPrefix + ComputerName), "User");

    public AdsiPrincipal GetUser(string name) {
        if (!name.Contains('/')) {
            name = ComputerName + "/" + name;
        }

        try {
            return ToPrincipal(CreateEntry($"{WinNtPrefix}{name},user"));
        } catch (PlatformNotSupportedException) {
            throw;
        } catch (Exception) {
            throw new AdsiResolutionException($"User '{name}' was not found.", name);
        }
    }

    public IReadOnlyList<AdsiPrincipal> GetMembers(AdsiPrincipal group) {
        var members = Invoke(CreateEntry(group.Path), "Members") as IEnumerable
            ?? Array.Empty<object>();

        var result = new List<AdsiPrincipal>();
        foreach (var member in members) {
            result.Add(ToPrincipal(member));
        }

        return result;
    }

    public bool IsMember(AdsiPrincipal group, AdsiPrincipal user) =>
        Invoke(CreateEntry(group.Path), "IsMember", user.Path) is bool value && value;

    public void AddMember(AdsiPrincipal group, AdsiPrincipal user) =>
        Invoke(CreateEntry(group.Path), "Add", user.Path);

    public void RemoveMember(AdsiPrincipal group, AdsiPrincipal user) =>
        Invoke(CreateEntry(group.Path), "Remove", user.Path);

    public IReadOnlyList<GroupObject> GetUserGroups(AdsiPrincipal user) {
        var (domain, username) = AdsiOperations.SplitAccountPath(user.Path);

        var result = new List<GroupObject>();
        foreach (var row in QueryWin32GroupUser()) {
            var part = GetRowPath(row, "PartComponent");
            if (part is null || !MatchesAccount(part, domain, username)) {
                continue;
            }

            var groupPath = GetRowPath(row, "GroupComponent");
            if (groupPath is null) {
                continue;
            }

            result.Add(ParseGroupPath(groupPath));
        }

        return result;
    }

    private static Type? LoadDirectoryEntryType() {
        try {
            return Assembly.Load("System.DirectoryServices")
                .GetType("System.DirectoryServices.DirectoryEntry");
        } catch {
            return null;
        }
    }

    private static Type? LoadManagementObjectSearcherType() {
        try {
            return Assembly.Load("System.Management")
                .GetType("System.Management.ManagementObjectSearcher");
        } catch {
            return null;
        }
    }

    private static object CreateEntry(string adsiPath) {
        var type = DirectoryEntryType.Value
            ?? throw new PlatformNotSupportedException(
                "System.DirectoryServices is not available on this runtime.");

        return Activator.CreateInstance(type, new object[] { adsiPath })
            ?? throw new InvalidOperationException($"Failed to create ADSI entry for '{adsiPath}'.");
    }

    private static IReadOnlyList<AdsiPrincipal> EnumerateChildren(object entry, string schemaClassName) {
        var result = new List<AdsiPrincipal>();
        var children = GetProperty(entry, "Children") as IEnumerable;
        if (children is null) {
            return result;
        }

        foreach (var child in children) {
            var principal = ToPrincipal(child);
            if (principal.SchemaClassName == schemaClassName) {
                result.Add(principal);
            }
        }

        return result;
    }

    private static object? Invoke(object entry, string methodName, params object[] args) {
        var type = DirectoryEntryType.Value
            ?? throw new PlatformNotSupportedException(
                "System.DirectoryServices is not available on this runtime.");

        var method = type.GetMethod("Invoke")
            ?? throw new InvalidOperationException("DirectoryEntry.Invoke is not available.");

        return method.Invoke(entry, new object[] { methodName, args });
    }

    private static object? GetProperty(object entry, string name) =>
        DirectoryEntryType.Value?.GetProperty(name)?.GetValue(entry);

    private static AdsiPrincipal ToPrincipal(object entry) {
        var name = GetProperty(entry, "Name") as string ?? string.Empty;
        var schema = GetProperty(entry, "SchemaClassName") as string ?? string.Empty;
        var path = GetProperty(entry, "Path") as string ?? string.Empty;
        var parent = GetProperty(entry, "Parent") is object parentEntry
            ? GetProperty(parentEntry, "Path") as string
            : null;

        return new AdsiPrincipal(name, schema, path, parent);
    }

    private static IEnumerable QueryWin32GroupUser() {
        var type = ManagementObjectSearcherType.Value
            ?? throw new PlatformNotSupportedException(
                "System.Management is not available on this runtime.");

        var searcher = Activator.CreateInstance(type, new object[] { "SELECT * FROM Win32_GroupUser" })
            ?? throw new InvalidOperationException("Failed to create Win32_GroupUser query.");

        var get = type.GetMethod("Get")
            ?? throw new InvalidOperationException("ManagementObjectSearcher.Get is not available.");

        return get.Invoke(searcher, null) as IEnumerable ?? Array.Empty<object>();
    }

    private static string? GetRowPath(object row, string propertyName) {
        var getPropertyValue = row.GetType().GetMethod("GetPropertyValue");
        var value = getPropertyValue?.Invoke(row, new object[] { propertyName });
        if (value is null) {
            return null;
        }

        if (value is string path) {
            return path;
        }

        // Reference properties surface as ManagementPath with a Path string.
        return value.GetType().GetProperty("Path")?.GetValue(value) as string;
    }

    private static bool MatchesAccount(string path, string domain, string username) {
        var domainToken = $"Domain=\"{domain}\"";
        var nameToken = $"Name=\"{username}\"";
        return path.IndexOf(domainToken, StringComparison.OrdinalIgnoreCase) >= 0
            && path.IndexOf(nameToken, StringComparison.OrdinalIgnoreCase) >= 0;
    }

    private static GroupObject ParseGroupPath(string path) =>
        new(ExtractToken(path, "Domain"), ExtractToken(path, "Name"), path);

    private static string ExtractToken(string path, string key) {
        var marker = key + "=\"";
        var start = path.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
        if (start < 0) {
            return string.Empty;
        }

        start += marker.Length;
        var end = path.IndexOf('"', start);
        return end < 0 ? path.Substring(start) : path.Substring(start, end - start);
    }

    private static string ComputerName =>
        Environment.GetEnvironmentVariable("COMPUTERNAME") is { Length: > 0 } name
            ? name
            : Environment.MachineName;
}
