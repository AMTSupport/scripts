// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using Compiler.Analyser;
using LanguageExt;
using LanguageExt.Common;
using System.Collections;
using System.Globalization;
using System.Management.Automation.Language;
using System.Text;

namespace Compiler.Test;

public class AstHelperTests {
    [TestCaseSource(typeof(TestData.ChildAndRoot), nameof(TestData.ChildAndRoot.Data))]
    public void FindRoot_ReturnsRootAst(
        Ast parentAst,
        Ast childAst,
        bool _,
        bool __) => Assert.That(AstHelper.FindRoot(childAst), Is.EqualTo(parentAst));

    [TestCaseSource(typeof(TestData.ChildAndRoot), nameof(TestData.ChildAndRoot.Data))]
    public void FindClosestParamBlock_ReturnsParamBlock(
        Ast _,
        Ast childAst,
        bool hasParamBlock,
        bool attributePresentOnClosestParamBlock) {
        if (!hasParamBlock) {
            Assert.That(AstHelper.FindClosestParamBlock(childAst), Is.Null);
        } else {
            var result = AstHelper.FindClosestParamBlock(childAst);

            Assert.Multiple(() => {
                Assert.That(result, Is.Not.Null);
                Assert.That(result, Is.TypeOf<ParamBlockAst>());

                if (attributePresentOnClosestParamBlock) {
                    Assert.That(result?.Attributes, Is.Not.Null);
                    Assert.That(result?.Attributes, Has.Count.EqualTo(1));

                    var attributes = SuppressAnalyserAttribute.FromAttributes(result!.Attributes);
                    var attribute = attributes.First();
                    Assert.That(attribute, Is.Not.Null);
                    Assert.That(attribute, Is.TypeOf<SuppressAnalyserAttribute>());
                }
            });
        }
    }

    [TestCaseSource(typeof(TestData.AstParser), nameof(TestData.AstParser.Data))]
    public void GetAstReportingErrors(
        string astContent,
        Option<string> filePath,
        IEnumerable<string> ignoredErrors,
        bool expectError
    ) {
        var result = AstHelper.GetAstReportingErrors(astContent, filePath, ignoredErrors, out _);

        Assert.Multiple(() => {
            if (expectError) {
                Assert.That(result.IsFail, Is.True);
                Assert.That((Error)result, Is.Not.Null);
            } else {
                Assert.That(result.IsSucc, Is.True);
                Assert.That((ScriptBlockAst)result, Is.Not.Null);

                if (filePath.IsNone) {
                    Assert.That(((ScriptBlockAst)result).Extent.File, Is.Null);
                } else {
                    Assert.That(((ScriptBlockAst)result).Extent.File, Is.EqualTo(filePath.Unwrap()));
                }

                Assert.That(((ScriptBlockAst)result).Extent.Text, Is.EqualTo(astContent));
            }
        });
    }

    [TestCaseSource(typeof(TestData.AstFinder), nameof(TestData.AstFinder.Functions))]
    public void FindAvailableFunctions(
        string astContent,
        IEnumerable<string> expectedFunctions,
        bool onlyExported
    ) {
        var ast = Parser.ParseInput(astContent, out _, out _);
        var result = AstHelper.FindAvailableFunctions(ast, onlyExported);

        Assert.Multiple(() => {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Has.Count.EqualTo(expectedFunctions.Count()));
            Assert.That(result, Has.All.Matches<FunctionDefinitionAst>(function => expectedFunctions.Contains(function.Name)));
        });
    }


    [TestCaseSource(typeof(TestData.AstFinder), nameof(TestData.AstFinder.Aliases))]
    public void FindAvailableAliases(
        string astContent,
        IEnumerable<string> expectedAliases,
        bool onlyExported
    ) {
        Console.WriteLine(astContent);
        var ast = AstHelper.GetAstReportingErrors(astContent, [], [], out _).ThrowIfFail();
        var result = AstHelper.FindAvailableAliases(ast, onlyExported);

        Assert.Multiple(() => {
            Assert.That(result, Is.Not.Null);
            Assert.That(result.Count(), Is.EqualTo(expectedAliases.Count()));
            Assert.That(result, Is.EquivalentTo(expectedAliases));
        });
    }

    [TestCaseSource(typeof(TestData.AstFinder), nameof(TestData.AstFinder.Namespaces))]
    public void FindDeclaredNamespaces(
        string astContent,
        IEnumerable<string> expectedNamespaces
    ) {
        var ast = Parser.ParseInput(astContent, out _, out _);
        var result = AstHelper.FindDeclaredNamespaces(ast);

        Assert.Multiple(() => {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Has.Count.EqualTo(expectedNamespaces.Count()));

            foreach (var expectedNamespace in expectedNamespaces) {
                Assert.That(result, Has.One.Matches<UsingStatementAst>(ns => ns.Name.Value == expectedNamespace));
            }
        });
    }

    [TestCaseSource(typeof(TestData.AstFinder), nameof(TestData.AstFinder.NameOnlyModules))]
    [TestCaseSource(typeof(TestData.AstFinder), nameof(TestData.AstFinder.ModuleSpecifications))]
    public void FindDeclaredModules(
        string astContent,
        Dictionary<string, Dictionary<string, object>> expectedModules,
        bool skipAstChecking
    ) {
        var ast = AstHelper.GetAstReportingErrors(astContent, Option<string>.None, ["ModuleNotFoundDuringParse"], out _).ThrowIfFail();
        var result = AstHelper.FindDeclaredModules(ast);

        Assert.Multiple(() => {
            Assert.That(result, Is.Not.Null);
            Assert.That(result, Has.Count.EqualTo(expectedModules.Count));
            Assert.That(result.Keys, Is.EquivalentTo(expectedModules.Keys));

            // We can't create an exact match for the returned ast so check it manually and remove it from the result
            foreach (var (moduleName, resultModule) in result) {
                if (resultModule.TryGetValue("AST", out var obj) && obj is Ast ast) {
                    var counterPart = expectedModules[moduleName];

                    if (!skipAstChecking) {
                        Assert.That(counterPart, Is.Not.Null);
                        Assert.That(counterPart, Has.Count.EqualTo(resultModule.Count));
                        Assert.That(counterPart, Contains.Key("AST"));
                        Assert.That(ast.Extent.Text, Is.EqualTo(expectedModules[moduleName]["AST"]));
                        counterPart.Remove("AST");
                    }

                    resultModule.Remove("AST");
                }
            }

            Assert.That(result, Is.EquivalentTo(expectedModules));
        });
    }
}

file static class TestData {
    internal static class ChildAndRoot {
        public static string USING_STATEMENTS = /*ps1*/ $$"""
        using assembly '{{typeof(AstHelper).Assembly.Location}}'
        using namespace Compiler.Analyser
        """;

        public static string ATTRIBUTE = /*ps1*/ """
        [SuppressAnalyser('UseOfUnknownFunction', 'unknown-function', 'Justification')]
        """;

        public static string NO_PARAM_GLOBAL = /*ps1*/ $$"""
        {{USING_STATEMENTS}}

        unknown-function
        """;

        public static string NO_PARAM_FUNCTION = /*ps1*/ $$"""
        {{USING_STATEMENTS}}

        function Test-Function {
            unknown-function
        }

        Test-Function
        """;

        public static string NO_ATTRIBUTE = /*ps1*/ $$"""
        {{USING_STATEMENTS}}

        function Test-Function {
            param($param1)

            unknown-function $param1
        }

        Test-Function
        """;

        public static string NO_ATTRIBUTE_NESTED = /*ps1*/ $$"""
        {{USING_STATEMENTS}}

        function Test-Function {
            param($param1)

            & {
                unknown-function $param1
            }
        }

        Test-Function
        """;

        public static string ATTRIBUTE_PARAM = /*ps1*/ $$"""
        {{USING_STATEMENTS}}

        function Test-Function {
            {{ATTRIBUTE}}
            param($param1)

            unknown-function $param1
        }

        Test-Function
        """;

        public static string ATTRIBUTE_GLOBAL = /*ps1*/ $$"""
        {{USING_STATEMENTS}}

        {{ATTRIBUTE}}
        param($param1)

        unknown-function $param1
        """;

        public static string ATTRIBUTE_NESTED_NO_PARAM = /*ps1*/ $$"""
        {{USING_STATEMENTS}}

        function Test-Function {
            {{ATTRIBUTE}}
            param($param1)

            & {
                unknown-function $param1
            }
        }

        Test-Function
        """;

        public static string ATTRIBUTE_NESTED_PARAM = /*ps1*/ $$"""
        {{USING_STATEMENTS}}

        function Test-Function {
            {{ATTRIBUTE}}
            param($param1)

            & {
                param()

                unknown-function $param1
            }
        }

        Test-Function
        """;

        public static Ast NO_PARAM_GLOBAL_AST = Parser.ParseInput(NO_PARAM_GLOBAL, out _, out _);
        public static Ast NO_PARAM_FUNCTION_AST = Parser.ParseInput(NO_PARAM_FUNCTION, out _, out _);
        public static Ast NO_ATTRIBUTE_AST = Parser.ParseInput(NO_ATTRIBUTE, out _, out _);
        public static Ast NO_ATTRIBUTE_NESTED_AST = Parser.ParseInput(NO_ATTRIBUTE_NESTED, out _, out _);
        public static Ast ATTRIBUTE_PARAM_AST = Parser.ParseInput(ATTRIBUTE_PARAM, out _, out _);
        public static Ast ATTRIBUTE_GLOBAL_AST = Parser.ParseInput(ATTRIBUTE_GLOBAL, out _, out _);
        public static Ast ATTRIBUTE_NESTED_NO_PARAM_AST = Parser.ParseInput(ATTRIBUTE_NESTED_NO_PARAM, out _, out _);
        public static Ast ATTRIBUTE_NESTED_PARAM_AST = Parser.ParseInput(ATTRIBUTE_NESTED_PARAM, out _, out _);

        public static IEnumerable Data {
            get {
                var commandFinder = new Func<Ast, bool>(ast => ast is CommandAst commandAst && commandAst.GetCommandName() == "unknown-function");

                yield return new TestCaseData(
                    NO_PARAM_GLOBAL_AST,
                    NO_PARAM_GLOBAL_AST.Find(commandFinder, true),
                    false,
                    false
                );

                yield return new TestCaseData(
                    NO_PARAM_FUNCTION_AST,
                    NO_PARAM_FUNCTION_AST.Find(commandFinder, true),
                    false,
                    false
                );

                yield return new TestCaseData(
                    NO_ATTRIBUTE_AST,
                    NO_ATTRIBUTE_AST.Find(commandFinder, true),
                    true,
                    false
                );

                yield return new TestCaseData(
                    NO_ATTRIBUTE_NESTED_AST,
                    NO_ATTRIBUTE_NESTED_AST.Find(commandFinder, true),
                    true,
                    false
                );

                yield return new TestCaseData(
                    ATTRIBUTE_PARAM_AST,
                    ATTRIBUTE_PARAM_AST.Find(commandFinder, true),
                    true,
                    true
                );

                yield return new TestCaseData(
                    ATTRIBUTE_GLOBAL_AST,
                    ATTRIBUTE_GLOBAL_AST.Find(commandFinder, true),
                    true,
                    true
                );

                yield return new TestCaseData(
                    ATTRIBUTE_NESTED_NO_PARAM_AST,
                    ATTRIBUTE_NESTED_NO_PARAM_AST.Find(commandFinder, true),
                    true,
                    true
                );

                yield return new TestCaseData(
                    ATTRIBUTE_NESTED_PARAM_AST,
                    ATTRIBUTE_NESTED_PARAM_AST.Find(commandFinder, true),
                    true,
                    false
                );
            }
        }
    }

    internal static class AstParser {
        private static readonly string[] SupressArgs = ["ModuleNotFoundDuringParse"];

        private static readonly string INVALID_AST = /*ps1*/ """
        some random invalid ast {
        """;

        private static readonly string VALID_AST = /*ps1*/ """
        function Test-Function {
            param($param1)

            Write-Host $param1
        }
        """;

        private static readonly string VALID_AST_WITH_ERROR = /*ps1*/ $$"""
        using module UnknownModule

        {{VALID_AST}}
        """;

        public static IEnumerable Data {
            get {
                yield return new TestCaseData(
                    VALID_AST,
                    Option<string>.Some("test.ps1"),
                    Array.Empty<string>(),
                    false
                ).SetName("No Error with file name");

                yield return new TestCaseData(
                    VALID_AST,
                    Option<string>.None,
                    Array.Empty<string>(),
                    false
                ).SetName("No Error without file name");

                yield return new TestCaseData(
                    INVALID_AST,
                    Option<string>.None,
                    Array.Empty<string>(),
                    true
                ).SetName("Error with invalid ast");

                yield return new TestCaseData(
                    VALID_AST_WITH_ERROR,
                    Option<string>.None,
                    Array.Empty<string>(),
                    true
                ).SetName("Error with valid ast and error");

                yield return new TestCaseData(
                    VALID_AST_WITH_ERROR,
                    Option<string>.None,
                    SupressArgs,
                    false
                ).SetName("Suppressed error with valid ast and error");
            }
        }
    }

    internal static class AstFinder {
        private static readonly string NOTHING_AST = /*ps1*/ """
        # Nothing
        """;

        public static IEnumerable Functions {
            get {
                var incorrectExportArgument = /*ps1*/ """
                function Test-Function { }
                Export-ModuleMember -Function (Get-Date)
                """;

                var singleFunctionNoExport = /*ps1*/ """
                function Test-Function { }
                """;

                var singleFunctionExported = /*ps1*/ $$"""
                {{singleFunctionNoExport}}
                Export-ModuleMember -Function Test-Function
                """;

                var multipleFunctionsNoExport = /*ps1*/ """
                function Test-Function1 { }
                function Test-Function2 { }
                function Test-Function3 { }
                """;

                var multipleFunctionsExported = /*ps1*/ $$"""
                {{multipleFunctionsNoExport}}
                Export-ModuleMember -Function Test-Function, Test-Function1, Test-Function2, Test-Function3
                """;

                var multipleExportCommands = /*ps1*/ $$"""
                {{singleFunctionExported}}
                {{multipleFunctionsNoExport}}
                """;

                var singleExportArray = new[] { "Test-Function" };
                var multipleExportArray = new[] { "Test-Function1", "Test-Function2", "Test-Function3" };
                var noExportArray = Array.Empty<string>();
                var allFunctionsArray = new[] { "Test-Function", "Test-Function1", "Test-Function2", "Test-Function3" };

                yield return new TestCaseData(NOTHING_AST, noExportArray, false);
                yield return new TestCaseData(NOTHING_AST, noExportArray, true);
                yield return new TestCaseData(incorrectExportArgument, noExportArray, true);

                yield return new TestCaseData(singleFunctionNoExport, singleExportArray, false);
                yield return new TestCaseData(singleFunctionNoExport, singleExportArray, true);
                yield return new TestCaseData(singleFunctionExported, singleExportArray, true);

                yield return new TestCaseData(multipleFunctionsNoExport, multipleExportArray, false);
                yield return new TestCaseData(multipleFunctionsNoExport, multipleExportArray, true);
                yield return new TestCaseData(multipleFunctionsExported, multipleExportArray, true);

                yield return new TestCaseData(multipleExportCommands, allFunctionsArray, false);
            }
        }

        public static IEnumerable Aliases {
            get {
                var templateByFunction = /*ps1*/ """
                <New-Alias -Name {name} -Value Test-Function{0}>
                """;

                var templateByAttribute = /*ps1*/ """
                <function Test-Function{0} {
                    [Alias('{name}')]
                    param()
                }>
                """;

                var nameTemplate = "Test-Alias{0}";
                var counts = new[] { 1, 2, 5 };
                for (var i = 0; i < counts.Length * 2; i++) {
                    var withExport = i % 2 == 0;
                    var count = counts[i / 2];
                    var (byFunctionContent, expectedByFunction) = GetTemplatedData(templateByFunction, nameTemplate, count, Environment.NewLine, "Alias", withExport);
                    var (byAttributeContent, expectedByAttribute) = GetTemplatedData(templateByAttribute, nameTemplate, count, Environment.NewLine, "Alias", withExport);

                    yield return new TestCaseData(byFunctionContent, expectedByFunction, withExport);
                    yield return new TestCaseData(byAttributeContent, expectedByAttribute, withExport);
                }
            }
        }

        private static (string, IEnumerable<string>) GetTemplatedData(
            string template,
            string nameTemplate,
            int count,
            string seperator,
            string exportType,
            bool withExport
        ) {
            var zoneStartIndex = template.IndexOf('<');
            var zoneEndIndex = template.IndexOf('>');

            var beforeZone = template[..zoneStartIndex];
            var afterZone = "";
            if (zoneEndIndex != -1 && zoneEndIndex < template.Length) afterZone = template[(zoneEndIndex + 1)..];

            var copyableZone = template[(zoneStartIndex + 1)..template.LastIndexOf('>')];

            var exportNames = new List<string>();
            var data = new StringBuilder().Append(beforeZone);
            for (var i = 0; i < count; i++) {
                var name = nameTemplate.Replace("{0}", i.ToString(CultureInfo.InvariantCulture));
                data.Append(copyableZone.Replace("{name}", name).Replace("{0}", i.ToString(CultureInfo.InvariantCulture)));
                if (i != count - 1) data.Append(seperator);

                exportNames.Add(name);
            }

            data.Append(afterZone);

            if (withExport) {
                data.AppendLine();
                data.Append("Export-ModuleMember -").Append(exportType).Append(' ');
                data.AppendJoin(',', exportNames);
            }

            return (data.ToString(), exportNames);
        }

        public static IEnumerable Namespaces {
            get {
                var singleNamespace = /*ps1*/ """
                using namespace System.Collections.Generic
                """;

                var multipleNamespaces = /*ps1*/ $$"""
                {{singleNamespace}}
                using namespace System.Management.Automation.Language
                using namespace System.Text.RegularExpressions
                """;

                var singleNamespaceArray = new[] { "System.Collections.Generic" };
                var multipleNamespaceArray = new[] { "System.Collections.Generic", "System.Management.Automation.Language", "System.Text.RegularExpressions" };

                yield return new TestCaseData(NOTHING_AST, Array.Empty<string>());
                yield return new TestCaseData(singleNamespace, singleNamespaceArray);
                yield return new TestCaseData(singleNamespace, singleNamespaceArray);
                yield return new TestCaseData(multipleNamespaces, multipleNamespaceArray);
            }
        }

        public static IEnumerable NameOnlyModules {
            get {
                var singleUsingModule = /*ps1*/ """
                using module BitLocker
                """;

                var singleRequireModule = /*ps1*/ """
                #Requires -Modules PnpDevice
                """;

                var multipleUsingModule = /*ps1*/ $$"""
                {{singleUsingModule}}
                using module SecureBoot
                using module DnsClient
                """;

                var multipleRequireModule = /*ps1*/ $$"""
                {{singleRequireModule}}
                #Requires -Modules AppBackgroundTask,SmbShare,PKI
                """;

                var mixedModules = /*ps1*/ $$"""
                {{multipleRequireModule}}
                {{multipleUsingModule}}
                """;

                var singleUsingModuleArray = new Dictionary<string, Dictionary<string, object>> {
                    ["BitLocker"] = new Dictionary<string, object> {
                        ["AST"] = "using module BitLocker"
                    }
                };

                var singleRequireModuleArray = new Dictionary<string, Dictionary<string, object>> {
                    ["PnpDevice"] = []
                };

                var multipleUsingModuleArray = new Dictionary<string, Dictionary<string, object>> {
                    ["BitLocker"] = new Dictionary<string, object> {
                        ["AST"] = "using module BitLocker"
                    },
                    ["SecureBoot"] = new Dictionary<string, object> {
                        ["AST"] = "using module SecureBoot"
                    },
                    ["DnsClient"] = new Dictionary<string, object> {
                        ["AST"] = "using module DnsClient"
                    }
                };

                var multipleRequireModuleArray = new Dictionary<string, Dictionary<string, object>> {
                    ["PnpDevice"] = [],
                    ["AppBackgroundTask"] = [],
                    ["SmbShare"] = [],
                    ["PKI"] = []
                };

                var mixedModulesArray = new Dictionary<string, Dictionary<string, object>> {
                    ["BitLocker"] = new(singleUsingModuleArray["BitLocker"]),
                    ["SecureBoot"] = new(multipleUsingModuleArray["SecureBoot"]),
                    ["PnpDevice"] = new(singleRequireModuleArray["PnpDevice"]),
                    ["DnsClient"] = new(multipleUsingModuleArray["DnsClient"]),
                    ["AppBackgroundTask"] = new(multipleRequireModuleArray["AppBackgroundTask"]),
                    ["SmbShare"] = new(multipleRequireModuleArray["SmbShare"]),
                    ["PKI"] = new(multipleRequireModuleArray["PKI"])
                };

                yield return new TestCaseData(NOTHING_AST, new Dictionary<string, Dictionary<string, object>>(), false);

                yield return new TestCaseData(singleUsingModule, singleUsingModuleArray, false);
                yield return new TestCaseData(singleRequireModule, singleRequireModuleArray, false);

                yield return new TestCaseData(multipleUsingModule, multipleUsingModuleArray, false);
                yield return new TestCaseData(multipleRequireModule, multipleRequireModuleArray, false);

                yield return new TestCaseData(mixedModules, mixedModulesArray, false);
            }
        }

        public static IEnumerable ModuleSpecifications {
            get {
                yield return new TestCaseData(
                    """
                    using module @{
                        ModuleName = 'BitLocker';
                        Guid = '0ff02bb8-300a-4262-ac08-e06dd810f1b6';
                        RequiredVersion = '1.0.0.0'
                    }
                    """,
                    new Dictionary<string, Dictionary<string, object>> {
                        ["BitLocker"] = new Dictionary<string, object> {
                            ["ModuleName"] = "BitLocker",
                            ["Guid"] = Guid.Parse("0ff02bb8-300a-4262-ac08-e06dd810f1b6"),
                            ["RequiredVersion"] = Version.Parse("1.0.0.0")
                        }
                    },
                    true
                );

                yield return new TestCaseData(
                    """
                    using module @{
                        ModuleName = 'PSReadLine';
                        Guid = '5714753b-2afd-4492-a5fd-01d9e2cff8b5';
                        ModuleVersion  = '2.3.2';
                        MaximumVersion = '2.3.5';
                    }
                    """,
                    new Dictionary<string, Dictionary<string, object>> {
                        ["PSReadLine"] = new Dictionary<string, object> {
                            ["ModuleName"] = "PSReadLine",
                            ["Guid"] = Guid.Parse("5714753b-2afd-4492-a5fd-01d9e2cff8b5"),
                            ["ModuleVersion"] = Version.Parse("2.3.2"),
                            ["MaximumVersion"] = Version.Parse("2.3.5")
                        }
                    },
                    true
                );
            }
        }
    }
}
