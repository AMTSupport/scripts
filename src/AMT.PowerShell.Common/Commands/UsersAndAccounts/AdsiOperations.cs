// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Generic;
using System.Management.Automation;

namespace AMT.PowerShell.Common.Commands.UsersAndAccounts;

internal static class AdsiOperations {
    // Injectable seam for tests; swaps the real ADSI backend for a fake.
    internal static IAdsiProvider Provider { get; set; } = new WinNtAdsiProvider();

    internal static bool IsSupported => Provider.IsSupported;

    internal static IReadOnlyList<AdsiPrincipal> GetGroups() {
        EnsureSupported();
        return Provider.GetGroups();
    }

    internal static AdsiPrincipal GetGroup(string name) {
        EnsureSupported();
        return Provider.GetGroup(name);
    }

    internal static IReadOnlyList<AdsiPrincipal> GetUsers() {
        EnsureSupported();
        return Provider.GetUsers();
    }

    internal static AdsiPrincipal GetUser(string name) {
        EnsureSupported();
        return Provider.GetUser(name);
    }

    internal static IReadOnlyList<AdsiPrincipal> GetMembers(AdsiPrincipal group) {
        EnsureSupported();
        var result = new List<AdsiPrincipal>();
        foreach (var member in Provider.GetMembers(group)) {
            if (!IsBuiltIn(member)) {
                result.Add(member);
            }
        }

        return result;
    }

    internal static bool IsMember(AdsiPrincipal group, AdsiPrincipal user) {
        EnsureSupported();
        return Provider.IsMember(group, user);
    }

    internal static void AddMember(AdsiPrincipal group, AdsiPrincipal user) {
        EnsureSupported();
        Provider.AddMember(group, user);
    }

    internal static void RemoveMember(AdsiPrincipal group, AdsiPrincipal user) {
        EnsureSupported();
        Provider.RemoveMember(group, user);
    }

    internal static IReadOnlyList<GroupObject> GetUserGroups(AdsiPrincipal user) {
        EnsureSupported();
        return Provider.GetUserGroups(user);
    }

    internal static AdsiPrincipal ResolveGroup(object? input) =>
        Resolve(input, "Group", name => Provider.GetGroup(name));

    internal static AdsiPrincipal ResolveUser(object? input) =>
        Resolve(input, "User", name => Provider.GetUser(name));

    internal static string ComputerName =>
        Environment.GetEnvironmentVariable("COMPUTERNAME") is { Length: > 0 } name
            ? name
            : Environment.MachineName;

    internal static (string Domain, string Name) SplitAccountPath(string path) {
        var value = path;
        const string prefix = "WinNT://";
        if (value.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) {
            value = value.Substring(prefix.Length);
        }

        value = StripClassSuffix(value);

        var parts = value.Split('/');
        var name = parts.Length > 0 ? parts[parts.Length - 1] : string.Empty;
        var domain = parts.Length > 1 ? parts[parts.Length - 2] : string.Empty;
        return (domain, name);
    }

    internal static string StripClassSuffix(string path) {
        if (path.EndsWith(",user", StringComparison.OrdinalIgnoreCase)) {
            return path.Substring(0, path.Length - ",user".Length);
        }

        if (path.EndsWith(",group", StringComparison.OrdinalIgnoreCase)) {
            return path.Substring(0, path.Length - ",group".Length);
        }

        return path;
    }

    private static AdsiPrincipal Resolve(
        object? input,
        string schemaClassName,
        Func<string, AdsiPrincipal> getByName) {
        EnsureSupported();
        input = Unwrap(input);

        if (input is string name) {
            if (name.Length == 0) {
                throw new AdsiResolutionException(
                    "An empty string was supplied, this is not a valid object.",
                    name);
            }

            if (schemaClassName == "User" && !name.Contains('/')) {
                name = ComputerName + "/" + name;
            }

            return getByName(name);
        }

        if (input is AdsiPrincipal principal) {
            if (!string.Equals(principal.SchemaClassName, schemaClassName, StringComparison.Ordinal)) {
                throw new AdsiResolutionException(
                    $"The supplied object is not a {schemaClassName}.",
                    principal);
            }

            return principal;
        }

        throw new AdsiResolutionException(
            $"The supplied object is not a {schemaClassName}.",
            input);
    }

    private static object? Unwrap(object? input) =>
        input is PSObject pso ? pso.BaseObject : input;

    private static bool IsBuiltIn(AdsiPrincipal principal) {
        var parent = principal.Parent;
        if (string.IsNullOrEmpty(parent)) {
            return false;
        }

        var value = parent!;
        const string prefix = "WinNT://";
        if (value.Length <= prefix.Length) {
            return true;
        }

        return value.Substring(prefix.Length).Equals("NT AUTHORITY", StringComparison.OrdinalIgnoreCase);
    }

    private static void EnsureSupported() {
        if (!Provider.IsSupported) {
            throw new PlatformNotSupportedException(
                "ADSI operations are only supported on Windows with the ADSI provider.");
        }
    }
}
