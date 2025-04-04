// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Collections;
using System.Management.Automation.Language;
using Compiler.Analyser;
using Compiler.Analyser.Rules;
using LanguageExt;

namespace Compiler.Test.Analyser;

[TestFixture]
public class SuppressionAttributeTests {
    [TestCaseSource(typeof(TestData), nameof(TestData.NoSuppressionAttribute))]
    public void FromAttributeAst_ReturnsNull(string astContent) {
        var attributes = TestData.GetAttributes(astContent);
        Assert.Multiple(() => {
            foreach (var attribute in attributes) {
                var result = SuppressAnalyserAttributeExt.FromAttributeAst(attribute).Unwrap();
                Assert.That(result, Is.EqualTo(Option<SuppressAnalyserAttribute>.None));
            }
        });
    }

    [TestCaseSource(typeof(TestData), nameof(TestData.SuppressionAttribute))]
    public void FromAttributeAst_ReturnsSuppression(string astContent, List<Suppression> expected) {
        var attributes = TestData.GetAttributes(astContent);
        var i = 0;
        foreach (var attribute in attributes) {
            var result = SuppressAnalyserAttributeExt.FromAttributeAst(attribute).Unwrap();
            if (!result.IsSome(out var attr)) continue;
            Assert.Multiple(() => {
                var suppression = attr.GetSuppression();

                Assert.That(suppression?.Type, Is.EqualTo(expected[i].Type));
                Assert.That(suppression?.Justification, Is.EqualTo(expected[i].Justification));

                if (expected[i].Data is IEnumerable data and not string) {
                    var j = 0;
                    foreach (var item in data) {
                        Assert.That(item, Is.EqualTo(((object[])expected[i].Data!)[j]));
                        j++;
                    }
                } else {
                    Assert.That(suppression?.Data, Is.EqualTo(expected[i].Data));
                }
            });
            i++;
        }
    }

    private static class TestData {
        public static IEnumerable NoSuppressionAttribute {
            get {
                yield return new TestCaseData("""
                [CmdletBinding()]
                param()
                """);

                yield return new TestCaseData("""
                function Test-Function {
                    param()
                }
                """);

                yield return new TestCaseData("""
                function Test-Function {
                    [CmdletBinding()]
                    [OutputType()]
                    [Alias('Test')]
                    param()
                }
                """);
            }
        }

        public static IEnumerable SuppressionAttribute {
            get {
                yield return new TestCaseData("""
                [SuppressAnalyser('UseOfUndefinedFunction', 'Function', 'Justification')]
                param()
                """,
                new List<Suppression> {
                    new(typeof(UseOfUndefinedFunction), "Function", "Justification")
                });

                yield return new TestCaseData("""
                function Test-Function {
                    [CmdletBinding()]
                    [OutputType()]
                    [Alias('Test')]
                    [SuppressAnalyser('UseOfUndefinedFunction', 'Certain-Function', 'Justification')]
                    param()
                }
                """,
                new List<Suppression> {
                    new(typeof(UseOfUndefinedFunction), "Certain-Function", "Justification")
                });

                yield return new TestCaseData("""
                function Test-Function {
                    [SuppressAnalyser('UseOfUndefinedFunction', 'This-Function', 'This Justification')]
                    [SuppressAnalyser('UseOfUndefinedFunction', 'That-Function', 'That Justification')]
                    param()
                }
                """,
                new List<Suppression> {
                    new(typeof(UseOfUndefinedFunction), "This-Function", "This Justification"),
                    new(typeof(UseOfUndefinedFunction), "That-Function", "That Justification")
                });

                yield return new TestCaseData("""
                function Test-Function {
                    [SuppressAnalyser('UseOfUndefinedFunction', ('This-Function', 'That-Function'), 'This and That Justification')]
                    param()
                }
                """,
                new List<Suppression> {
                    new(typeof(UseOfUndefinedFunction), new object[] { "This-Function", "That-Function" }, "This and That Justification")
                });

                yield return new TestCaseData("""
                function Test-Function {
                    [SuppressAnalyser('UseOfUndefinedFunction', 'This-Function', Justification = 'This Justification')]
                    [SuppressAnalyserAttribute('UseOfUndefinedFunction', 'That-Function', Justification = 'That Justification')]
                    [Compiler.Analyser.SuppressAnalyser('UseOfUndefinedFunction', 'Other-Function', Justification = 'Other Justification')]
                    [Compiler.Analyser.SuppressAnalyserAttribute('UseOfUndefinedFunction', 'Another-Function', Justification = 'Another Justification')]
                    [SuppressAnalyser('UseOfUndefinedFunction', 'Other-Function')]
                    [SuppressAnalyserAttribute('UseOfUndefinedFunction', 'Another-Function')]
                    [Compiler.Analyser.SuppressAnalyser('UseOfUndefinedFunction', 'This-Function')]
                    [Compiler.Analyser.SuppressAnalyserAttribute('UseOfUndefinedFunction', 'That-Function')]
                    param()
                }
                """,
                new List<Suppression> {
                    new(typeof(UseOfUndefinedFunction), "This-Function", "This Justification"),
                    new(typeof(UseOfUndefinedFunction), "That-Function", "That Justification"),
                    new(typeof(UseOfUndefinedFunction), "Other-Function", "Other Justification"),
                    new(typeof(UseOfUndefinedFunction), "Another-Function", "Another Justification"),
                    new(typeof(UseOfUndefinedFunction), "This-Function", null),
                    new(typeof(UseOfUndefinedFunction), "That-Function", null),
                    new(typeof(UseOfUndefinedFunction), "Other-Function", null),
                    new(typeof(UseOfUndefinedFunction), "Another-Function", null)
                });
            }
        }

        public static IEnumerable<AttributeAst> GetAttributes(string astContent) {
            var ast = Parser.ParseInput(astContent, out _, out var errors);
            Assert.That(errors, Is.Empty);
            return ast.FindAll(ast => ast is AttributeAst, true).Cast<AttributeAst>();
        }
    }
}
