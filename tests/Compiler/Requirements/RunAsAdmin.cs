// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Security.Cryptography;
using System.Text;
using Compiler.Requirements;

namespace Compiler.Test.Requirements;

[TestFixture]
public class RunAsAdminRequirementTests {
    [Test]
    public void Hash_ShouldReturnHashOfString() {
        var requirement = new RunAsAdminRequirement();
        var hash = requirement.Hash;

        Assert.That(hash, Is.EqualTo(SHA256.HashData(Encoding.UTF8.GetBytes("#Requires -RunAsAdministrator"))));
    }

    [Test]
    public void Hash_ShouldAlwaysBeTheSame() {
        var requirement = new RunAsAdminRequirement();
        var requirement1 = new RunAsAdminRequirement();

        Assert.That(requirement.Hash, Is.EqualTo(requirement1.Hash));
    }

    [Test]
    public void GetInsertableLine_ShouldReturnString() {
        var requirement = new RunAsAdminRequirement();

        var insertableLine = requirement.GetInsertableLine([]);

        Assert.That(insertableLine, Is.EqualTo("#Requires -RunAsAdministrator"));
    }

    [Test]
    public void IsCompatibleWith_ShouldReturnTrue() {
        var requirement = new RunAsAdminRequirement();

        var isCompatible = requirement.IsCompatibleWith(new RunAsAdminRequirement());

        Assert.That(isCompatible, Is.True);
    }
}
