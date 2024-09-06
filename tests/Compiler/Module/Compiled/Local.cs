// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using System.Management.Automation.Language;
using System.Reflection;
using Compiler.Module.Compiled;
using Compiler.Requirements;
using Compiler.Text;
using Moq;
using QuikGraph;
using RealCompiled = Compiler.Module.Compiled.Compiled;

namespace Compiler.Test.Module.Compiled;

[TestFixture]
public class CompiledLocalModuleTests {
    [Test, Repeat(10), Parallelizable]
    public void StringifyContent_ReturnsValidAstContent() {
        var module = TestData.GetRandomCompiledModule();
        var stringifiedContent = module.StringifyContent();
        Assert.Multiple(() => {
            var ast = Parser.ParseInput(stringifiedContent, out _, out var errors);
            Assert.That(errors, Is.Empty);
            Assert.That(ast, Is.Not.Null);
        });
    }
}

file static class TestData {
    public static RealCompiled GetRandomCompiledModule(CompiledLocalModule? parent = null, int depLevel = 0) {
        var random = TestContext.CurrentContext.Random;
        var createDependencies = depLevel < 3 && random.NextBool();
        var scriptParent = parent as CompiledScript ?? parent?.GetRootParent() as CompiledScript;

        var createLocalModule = parent is null || random.NextBool();
        if (createLocalModule) {
            var document = CompiledDocument.FromBuilder(new TextEditor(new TextDocument(["Write-Host 'Hello, World!'"]))).Unwrap();
            var modulePath = TestContext.CurrentContext.WorkDirectory + $"/{random.GetString(6)}.psm1";
            File.Create(modulePath).Close();
            var moduleSpec = new PathedModuleSpec(modulePath);
            var requirementGroup = new RequirementGroup();
            requirementGroup.AddRequirement(new RunAsAdminRequirement());

            // Gotta create a script module
            if (depLevel == 0 || scriptParent is null) {
                var scriptMock = new Mock<CompiledScript>(moduleSpec, document, requirementGroup) {
                    CallBase = true
                };

                var graph = new BidirectionalGraph<RealCompiled, Edge<RealCompiled>>();
                graph.AddVertex(scriptMock.Object);
                graph.EdgeAdded += edge => {
                    edge.Target.Parents.Add(edge.Source);
                    edge.Target.GetRootParent().Requirements.AddRequirement(edge.Target.ModuleSpec);
                };

                if (createDependencies) {
                    var dependencies = new List<RealCompiled>();
                    for (var i = 0; i < random.Next(1, 5); i++) {
                        var dependency = GetRandomCompiledModule(scriptMock.Object, depLevel + 1);
                        dependencies.Add(dependency);
                        graph.AddVertex(dependency);
                        graph.AddEdge(new Edge<RealCompiled>(scriptMock.Object, dependency));
                    }
                }

                return scriptMock.Object;
            } else {
                var module = new CompiledLocalModule(moduleSpec, document, requirementGroup);
                scriptParent!.Graph.AddVerticesAndEdge(new Edge<RealCompiled>(scriptParent, module));
                module.Parents.Add(scriptParent);

                if (createDependencies) {
                    var dependencies = new List<RealCompiled>();
                    for (var i = 0; i < random.Next(1, 5); i++) {
                        var dependency = GetRandomCompiledModule(module, depLevel + 1);
                        dependencies.Add(dependency);
                        scriptParent.Graph.AddVertex(dependency);
                        scriptParent.Graph.AddEdge(new Edge<RealCompiled>(module, dependency));
                    }
                }

                return module;
            }
        } else {
            var remoteModule = CompiledRemoteModuleTests.TestData.GetTestRemoteModule();
            scriptParent!.Graph.AddVerticesAndEdge(new Edge<RealCompiled>(scriptParent, remoteModule));

            return remoteModule;
        }
    }
}
