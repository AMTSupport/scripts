using static Compiler.Module.Compiled.Compiled;
using Compiler.Requirements;
using System.Collections;

namespace Compiler.Test.Module.Compiled;

[TestFixture]
public class CompiledTests
{
    [TestCaseSource(typeof(TestData), nameof(TestData.AddRequirementHashData)), Repeat(10)]
    public void AddRequirementHashBytes_AlwaysSameResult(
        byte[] hashableBytes,
        RequirementGroup requirementGroup
    )
    {
        var random = new Random();
        List<byte> bytesList;
        var hashResults = new List<byte[]>();
        do
        {
            bytesList = new List<byte>(hashableBytes);
            AddRequirementHashBytes(bytesList, requirementGroup);
            hashResults.Add([.. hashableBytes]);
        } while (hashResults.Count < random.Next(2, 5));

        var firstResult = hashResults.First();
        Assert.Multiple(() =>
        {
            foreach (var result in hashResults)
            {
                Assert.That(result, Is.EqualTo(firstResult));
            }
        });
    }
}

file static class TestData
{
    public static IEnumerable AddRequirementHashData
    {
        get
        {
            var random = new Random();
            var hashableBytes = new byte[random.Next(10, 100)];
            random.NextBytes(hashableBytes);

            yield return new TestCaseData(
                hashableBytes,
                new RequirementGroup()
                {
                    StoredRequirements = {
                        { typeof(ModuleSpec), new HashSet<Requirement> {
                            new ModuleSpec("PSWindowsUpdate"),
                            new ModuleSpec("PSReadLine", requiredVersion: new (2, 3, 5)),
                            new PathedModuleSpec($"{Environment.CurrentDirectory}/../../../../../src/common/Environment.psm1")
                        } },
                        { typeof(PSEditionRequirement), new HashSet<Requirement> {
                            new PSEditionRequirement(PSEdition.Core)
                        } },
                        { typeof(UsingNamespace), new HashSet<Requirement> {
                            new UsingNamespace("System.Collections"),
                            new UsingNamespace("System.Diagnostics")
                        } },
                    }
                }
            ).SetName("Multiple types of Requirements");

            yield return new TestCaseData(
                hashableBytes,
                new RequirementGroup()
                {
                    StoredRequirements = {
                        { typeof(ModuleSpec), new HashSet<Requirement> {
                            new PathedModuleSpec($"{Environment.CurrentDirectory}/../../../../../src/common/Environment.psm1")
                        } },
                    }
                }
            ).SetName("Single type of Requirement");
        }
    }
}
