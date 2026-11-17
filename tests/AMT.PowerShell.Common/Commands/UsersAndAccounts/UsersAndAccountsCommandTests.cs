// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using AMT.PowerShell.Common.Commands.UsersAndAccounts;

namespace AMT.PowerShell.Common.Tests.Commands.UsersAndAccounts;

[TestFixture]
[NonParallelizable]
public sealed class UsersAndAccountsCommandTests {
    private FakeProvider _provider = null!;

    [SetUp]
    public void SetUp() {
        _provider = new FakeProvider();
        AdsiOperations.Provider = _provider;
    }

    [TearDown]
    public void TearDown() => AdsiOperations.Provider = new WinNtAdsiProvider();

    // ── Resolve-by-name / resolve-by-object ─────────────────────────────────

    [Test]
    public void GetGroupByInputOrName_ResolvesByName() {
        var group = Principal("Admins", "Group");
        _provider.Groups.Add(group);

        var result = InvokeSingle<AdsiPrincipal>("Get-GroupByInputOrName", ("InputObject", "Admins"));
        Assert.That(result.Name, Is.EqualTo("Admins"));
    }

    [Test]
    public void GetGroupByInputOrName_ResolvesByObject() {
        var group = Principal("Admins", "Group");
        _provider.Groups.Add(group);

        var result = InvokeSingle<AdsiPrincipal>("Get-GroupByInputOrName", ("InputObject", group));
        Assert.That(result, Is.SameAs(group));
    }

    [Test]
    public void GetUserByInputOrName_ResolvesByName() {
        var user = Principal("localadmin", "User");
        _provider.Users.Add(user);

        var result = InvokeSingle<AdsiPrincipal>("Get-UserByInputOrName", ("InputObject", "TESTDOMAIN/localadmin"));
        Assert.That(result.Name, Is.EqualTo("localadmin"));
    }

    [Test]
    public void GetUserByInputOrName_ResolvesByObject() {
        var user = Principal("localadmin", "User");
        _provider.Users.Add(user);

        var result = InvokeSingle<AdsiPrincipal>("Get-UserByInputOrName", ("InputObject", user));
        Assert.That(result, Is.SameAs(user));
    }

    [Test]
    public void GetGroupByInputOrName_WritesError_WhenWrongSchema() {
        var user = Principal("localadmin", "User");
        _provider.Users.Add(user);

        var invocation = InvokeCommand("Get-GroupByInputOrName", ("InputObject", user));
        Assert.Multiple(() => {
            Assert.That(invocation.HadErrors, Is.True);
            Assert.That(invocation.Results, Is.Empty);
        });
    }

    // ── Membership test/add/remove + idempotency ────────────────────────────

    [Test]
    public void TestMemberOfGroup_ReturnsTrue_WhenMember() {
        var group = Principal("Admins", "Group");
        var user = Principal("localadmin", "User");
        _provider.Groups.Add(group);
        _provider.Users.Add(user);
        _provider.Membership.Add(Key(group, user));

        var result = InvokeSingle<bool>(
            "Test-MemberOfGroup",
            ("Group", "Admins"),
            ("User", "TESTDOMAIN/localadmin"));

        Assert.That(result, Is.True);
    }

    [Test]
    public void TestMemberOfGroup_ReturnsFalse_WhenNotMember() {
        var group = Principal("Admins", "Group");
        var user = Principal("localadmin", "User");
        _provider.Groups.Add(group);
        _provider.Users.Add(user);

        var result = InvokeSingle<bool>(
            "Test-MemberOfGroup",
            ("Group", "Admins"),
            ("User", "TESTDOMAIN/localadmin"));

        Assert.That(result, Is.False);
    }

    [Test]
    public void AddMemberToGroup_ReturnsTrue_AndRecordsAdd() {
        var group = Principal("Admins", "Group");
        var user = Principal("localadmin", "User");
        _provider.Groups.Add(group);
        _provider.Users.Add(user);

        var result = InvokeSingle<bool>(
            "Add-MemberToGroup",
            ("Group", "Admins"),
            ("User", "TESTDOMAIN/localadmin"));

        Assert.Multiple(() => {
            Assert.That(result, Is.True);
            Assert.That(_provider.Added, Has.Count.EqualTo(1));
            Assert.That(_provider.Membership, Does.Contain(Key(group, user)));
        });
    }

    [Test]
    public void AddMemberToGroup_ReturnsFalse_WhenAlreadyMember() {
        var group = Principal("Admins", "Group");
        var user = Principal("localadmin", "User");
        _provider.Groups.Add(group);
        _provider.Users.Add(user);
        _provider.Membership.Add(Key(group, user));

        var result = InvokeSingle<bool>(
            "Add-MemberToGroup",
            ("Group", "Admins"),
            ("User", "TESTDOMAIN/localadmin"));

        Assert.Multiple(() => {
            Assert.That(result, Is.False);
            Assert.That(_provider.Added, Is.Empty);
        });
    }

    [Test]
    public void RemoveMemberFromGroup_ReturnsTrue_AndRecordsRemove() {
        var group = Principal("Admins", "Group");
        var user = Principal("localadmin", "User");
        _provider.Groups.Add(group);
        _provider.Users.Add(user);
        _provider.Membership.Add(Key(group, user));

        var result = InvokeSingle<bool>(
            "Remove-MemberFromGroup",
            ("Group", "Admins"),
            ("Member", "TESTDOMAIN/localadmin"));

        Assert.Multiple(() => {
            Assert.That(result, Is.True);
            Assert.That(_provider.Removed, Has.Count.EqualTo(1));
            Assert.That(_provider.Membership, Does.Not.Contain(Key(group, user)));
        });
    }

    [Test]
    public void RemoveMemberFromGroup_ReturnsFalse_WhenNotMember() {
        var group = Principal("Admins", "Group");
        var user = Principal("localadmin", "User");
        _provider.Groups.Add(group);
        _provider.Users.Add(user);

        var result = InvokeSingle<bool>(
            "Remove-MemberFromGroup",
            ("Group", "Admins"),
            ("Member", "TESTDOMAIN/localadmin"));

        Assert.Multiple(() => {
            Assert.That(result, Is.False);
            Assert.That(_provider.Removed, Is.Empty);
        });
    }

    // ── Get-UserGroups with provider seam ───────────────────────────────────

    [Test]
    public void GetUserGroups_ReturnsGroupsForUser() {
        var admins = Principal("Admins", "Group");
        var users = Principal("Users", "Group");
        var other = Principal("Other", "Group");
        var localadmin = Principal("localadmin", "User");

        _provider.Groups.Add(admins);
        _provider.Groups.Add(users);
        _provider.Groups.Add(other);
        _provider.Users.Add(localadmin);
        _provider.Membership.Add(Key(admins, localadmin));
        _provider.Membership.Add(Key(users, localadmin));

        var invocation = InvokeCommand("Get-UserGroups", ("User", "TESTDOMAIN/localadmin"));

        Assert.Multiple(() => {
            Assert.That(invocation.HadErrors, Is.False);
            var groups = invocation.Results.Select(r => (GroupObject)r.BaseObject).ToArray();
            Assert.That(groups.Select(g => g.Name), Is.EquivalentTo(new[] { "Admins", "Users" }));
            Assert.That(groups.Select(g => g.Domain), Is.All.EqualTo("TESTDOMAIN"));
        });
    }

    // ── Get-MembersOfGroup filters built-in principals ──────────────────────

    [Test]
    public void GetMembersOfGroup_FiltersBuiltInPrincipals() {
        var group = Principal("Admins", "Group");
        var member = Principal("localadmin", "User");
        var builtIn = Principal("SYSTEM", "User", parent: "WinNT://NT AUTHORITY");

        _provider.Groups.Add(group);
        _provider.Users.Add(member);
        _provider.Users.Add(builtIn);
        _provider.Membership.Add(Key(group, member));
        _provider.Membership.Add(Key(group, builtIn));

        var invocation = InvokeCommand("Get-MembersOfGroup", ("Group", "Admins"));

        Assert.Multiple(() => {
            Assert.That(invocation.HadErrors, Is.False);
            var names = invocation.Results.Select(r => ((AdsiPrincipal)r.BaseObject).Name).ToArray();
            Assert.That(names, Is.EquivalentTo(new[] { "localadmin" }));
        });
    }

    // ── Format-ADSIUser name/domain extraction ──────────────────────────────

    [Test]
    public void FormatADSIUser_ExtractsNameAndDomain() {
        var user = Principal("localadmin", "User", path: "WinNT://TESTDOMAIN/localadmin");

        var result = InvokeSingle<Hashtable>("Format-ADSIUser", ("User", user));

        Assert.Multiple(() => {
            Assert.That(result["Name"], Is.EqualTo("localadmin"));
            Assert.That(result["Domain"], Is.EqualTo("TESTDOMAIN"));
        });
    }

    [Test]
    public void FormatADSIUser_ReturnsOneResultPerUser() {
        var user1 = Principal("a", "User", path: "WinNT://DOM/a");
        var user2 = Principal("b", "User", path: "WinNT://DOM/b");

        var invocation = InvokeCommand("Format-ADSIUser", ("User", new[] { user1, user2 }));

        Assert.Multiple(() => {
            Assert.That(invocation.HadErrors, Is.False);
            Assert.That(invocation.Results, Has.Count.EqualTo(2));
        });
    }

    [Test]
    public void FormatADSIUser_WritesError_WhenNonUser() {
        var group = Principal("Admins", "Group", path: "WinNT://TESTDOMAIN/Admins");

        var invocation = InvokeCommand("Format-ADSIUser", ("User", group));

        Assert.Multiple(() => {
            Assert.That(invocation.HadErrors, Is.True);
            Assert.That(invocation.Results, Is.Empty);
        });
    }

    // ── Unsupported platform surfaces an actionable error ───────────────────

    [Test]
    public void GetGroup_WritesError_WhenUnsupportedPlatform() {
        _provider.Supported = false;

        var invocation = InvokeCommand("Get-Group");

        Assert.Multiple(() => {
            Assert.That(invocation.HadErrors, Is.True);
            Assert.That(invocation.Results, Is.Empty);
        });
    }

    // ── Not-found surfaces a shaped error ───────────────────────────────────

    [Test]
    public void GetGroup_WritesError_WhenNotFound() {
        var invocation = InvokeCommand("Get-Group", ("Name", "Missing"));

        Assert.Multiple(() => {
            Assert.That(invocation.HadErrors, Is.True);
            Assert.That(invocation.Results, Is.Empty);
        });
    }

    [Test]
    public void GetUser_WritesError_WhenNotFound() {
        var invocation = InvokeCommand("Get-User", ("Name", "TESTDOMAIN/missing"));

        Assert.Multiple(() => {
            Assert.That(invocation.HadErrors, Is.True);
            Assert.That(invocation.Results, Is.Empty);
        });
    }

    // ── Helpers ─────────────────────────────────────────────────────────────

    private static AdsiPrincipal Principal(
        string name,
        string schema,
        string? path = null,
        string? parent = null) =>
        new(name, schema, path ?? $"WinNT://TESTDOMAIN/{name}", parent);

    private static string Key(AdsiPrincipal group, AdsiPrincipal user) =>
        $"{group.Path}|{user.Path}";

    private static T InvokeSingle<T>(string commandName, params (string Name, object? Value)[] parameters) {
        var invocation = InvokeCommand(commandName, parameters);
        Assert.That(invocation.Results, Has.Count.EqualTo(1));
        Assert.That(invocation.Results[0].BaseObject, Is.TypeOf<T>());
        return (T)invocation.Results[0].BaseObject;
    }

    private static CommandResult InvokeCommand(string commandName, params (string Name, object? Value)[] parameters) {
        var iss = InitialSessionState.CreateDefault2();
        iss.Commands.Add(new SessionStateCmdletEntry("Get-User", typeof(GetUserCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Get-UserGroups", typeof(GetUserGroupsCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Get-Group", typeof(GetGroupCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Get-MembersOfGroup", typeof(GetMembersOfGroupCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Test-MemberOfGroup", typeof(TestMemberOfGroupCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Add-MemberToGroup", typeof(AddMemberToGroupCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Remove-MemberFromGroup", typeof(RemoveMemberFromGroupCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Format-ADSIUser", typeof(FormatADSIUserCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Get-GroupByInputOrName", typeof(GetGroupByInputOrNameCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Get-UserByInputOrName", typeof(GetUserByInputOrNameCommand), null));

        using var runspace = RunspaceFactory.CreateRunspace(iss);
        runspace.Open();

        using var ps = System.Management.Automation.PowerShell.Create();
        ps.Runspace = runspace;
        ps.AddCommand(commandName);

        foreach (var (name, value) in parameters) {
            ps.AddParameter(name, value);
        }

        var results = ps.Invoke();
        var errors = ps.Streams.Error.Select(e => e.ToString()).ToArray();
        return new CommandResult(results, ps.HadErrors, errors);
    }

    private sealed class FakeProvider : IAdsiProvider {
        public bool Supported { get; set; } = true;

        public List<AdsiPrincipal> Groups { get; } = new();

        public List<AdsiPrincipal> Users { get; } = new();

        public HashSet<string> Membership { get; } = new();

        public List<string> Added { get; } = new();

        public List<string> Removed { get; } = new();

        public bool IsSupported => Supported;

        public IReadOnlyList<AdsiPrincipal> GetGroups() => Groups;

        public AdsiPrincipal GetGroup(string name) =>
            Groups.FirstOrDefault(g => g.Name == name)
            ?? throw new AdsiResolutionException($"Group '{name}' was not found.", name);

        public IReadOnlyList<AdsiPrincipal> GetUsers() => Users;

        public AdsiPrincipal GetUser(string name) {
            var parts = name.Split('/');
            var username = parts.Length > 0 ? parts[parts.Length - 1] : name;
            return Users.FirstOrDefault(u => u.Name == username)
                ?? throw new AdsiResolutionException($"User '{name}' was not found.", name);
        }

        public IReadOnlyList<AdsiPrincipal> GetMembers(AdsiPrincipal group) {
            var result = new List<AdsiPrincipal>();
            foreach (var user in Users) {
                if (Membership.Contains(Key(group, user))) {
                    result.Add(user);
                }
            }

            return result;
        }

        public bool IsMember(AdsiPrincipal group, AdsiPrincipal user) =>
            Membership.Contains(Key(group, user));

        public void AddMember(AdsiPrincipal group, AdsiPrincipal user) {
            Membership.Add(Key(group, user));
            Added.Add(Key(group, user));
        }

        public void RemoveMember(AdsiPrincipal group, AdsiPrincipal user) {
            Membership.Remove(Key(group, user));
            Removed.Add(Key(group, user));
        }

        public IReadOnlyList<GroupObject> GetUserGroups(AdsiPrincipal user) {
            var result = new List<GroupObject>();
            foreach (var group in Groups) {
                if (Membership.Contains(Key(group, user))) {
                    result.Add(new GroupObject(
                        "TESTDOMAIN",
                        group.Name,
                        $"Win32_Group.Domain=\"TESTDOMAIN\",Name=\"{group.Name}\""));
                }
            }

            return result;
        }

        private static string Key(AdsiPrincipal group, AdsiPrincipal user) =>
            $"{group.Path}|{user.Path}";
    }

    private sealed record CommandResult(
        IReadOnlyList<PSObject> Results,
        bool HadErrors,
        IReadOnlyList<string> Errors);
}
