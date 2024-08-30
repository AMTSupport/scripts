// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using Compiler.Analyser;
using System.Collections;
using System.Management.Automation.Language;

namespace Compiler.Test;

public class AstHelperTests {
    [TestCaseSource(typeof(TestData), nameof(TestData.ChildAndRoot))]
    public void FindRoot_ReturnsRootAst(
        Ast parentAst,
        Ast childAst,
        bool _,
        bool __) => Assert.That(AstHelper.FindRoot(childAst), Is.EqualTo(parentAst));

    [TestCaseSource(typeof(TestData), nameof(TestData.ChildAndRoot))]
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
}

file static class TestData {
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

    public static Ast NO_PRAM_GLOBAL_AST = Parser.ParseInput(NO_PARAM_GLOBAL, out _, out _);
    public static Ast NO_PARAM_FUNCTION_AST = Parser.ParseInput(NO_PARAM_FUNCTION, out _, out _);
    public static Ast NO_ATTRIBUTE_AST = Parser.ParseInput(NO_ATTRIBUTE, out _, out _);
    public static Ast NO_ATTRIBUTE_NESTED_AST = Parser.ParseInput(NO_ATTRIBUTE_NESTED, out _, out _);
    public static Ast ATTRIBUTE_PARAM_AST = Parser.ParseInput(ATTRIBUTE_PARAM, out _, out _);
    public static Ast ATTRIBUTE_GLOBAL_AST = Parser.ParseInput(ATTRIBUTE_GLOBAL, out _, out _);
    public static Ast ATTRIBUTE_NESTED_NO_PARAM_AST = Parser.ParseInput(ATTRIBUTE_NESTED_NO_PARAM, out _, out _);
    public static Ast ATTRIBUTE_NESTED_PARAM_AST = Parser.ParseInput(ATTRIBUTE_NESTED_PARAM, out _, out _);

    public static IEnumerable ChildAndRoot {
        get {
            var commandFinder = new Func<Ast, bool>(ast => ast is CommandAst commandAst && commandAst.GetCommandName() == "unknown-function");

            yield return new TestCaseData(
                NO_PRAM_GLOBAL_AST,
                NO_PRAM_GLOBAL_AST.Find(commandFinder, true),
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
