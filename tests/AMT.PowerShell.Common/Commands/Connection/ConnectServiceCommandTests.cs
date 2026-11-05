// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using AMT.PowerShell.Common.Commands.Connection;

namespace AMT.PowerShell.Common.Tests.Commands.Connection;

[TestFixture]
[NonParallelizable]
public sealed class ConnectServiceCommandTests {
    [TearDown]
    public void TearDown() {
        ConnectionRuntime.ServiceResolverOverride = null;
        ConnectionRuntime.ConfirmationOverride = null;
    }

    [Test]
    public void ConnectService_WhenDisconnected_Connects() {
        var graph = new FakeService("Graph") { ContextValue = null };
        ConnectionRuntime.ServiceResolverOverride = name => name == "Graph" ? graph.Definition : null;

        var result = InvokeCommand(("Services", new[] { "Graph" }));

        Assert.Multiple(() => {
            Assert.That(result.HadErrors, Is.False);
            Assert.That(graph.ConnectCalls, Is.EqualTo(1));
            Assert.That(graph.ContextValue, Is.EqualTo("Graph@example.com"));
        });
    }

    [Test]
    public void ConnectService_CheckOnlyWhenDisconnected_ThrowsNotConnected() {
        var graph = new FakeService("Graph") { ContextValue = null };
        ConnectionRuntime.ServiceResolverOverride = name => name == "Graph" ? graph.Definition : null;

        try {
            InvokeCommand(
                ("Services", new[] { "Graph" }),
                ("CheckOnly", SwitchParameter.Present));
            Assert.Fail("Expected CmdletInvocationException was not thrown.");
        } catch (CmdletInvocationException ex) {
            Assert.Multiple(() => {
                Assert.That(ex.ErrorRecord.FullyQualifiedErrorId, Does.StartWith("FailedExit"));
                Assert.That(ex.ErrorRecord.TargetObject, Is.EqualTo(1002));
            });
        }

        Assert.That(graph.ConnectCalls, Is.EqualTo(0));
    }

    [Test]
    public void ConnectService_ConnectFailure_RoutesFailedExit1003() {
        var graph = new FakeService("Graph") { ContextValue = null, ConnectThrows = new InvalidOperationException("connect failed") };
        ConnectionRuntime.ServiceResolverOverride = name => name == "Graph" ? graph.Definition : null;

        try {
            InvokeCommand(("Services", new[] { "Graph" }));
            Assert.Fail("Expected CmdletInvocationException was not thrown.");
        } catch (CmdletInvocationException ex) {
            Assert.Multiple(() => {
                Assert.That(ex.ErrorRecord.FullyQualifiedErrorId, Does.StartWith("FailedExit"));
                Assert.That(ex.ErrorRecord.TargetObject, Is.EqualTo(1003));
            });
        }
    }

    [Test]
    public void ConnectService_DisconnectFailure_RoutesFailedExit1001() {
        var graph = new FakeService("Graph") {
            ContextValue = "user@example.com",
            IsValid = _ => false,
            DisconnectThrows = new InvalidOperationException("disconnect failed"),
        };
        ConnectionRuntime.ServiceResolverOverride = name => name == "Graph" ? graph.Definition : null;

        try {
            InvokeCommand(("Services", new[] { "Graph" }), ("Scopes", new[] { "Mail.Read" }));
            Assert.Fail("Expected CmdletInvocationException was not thrown.");
        } catch (CmdletInvocationException ex) {
            Assert.Multiple(() => {
                Assert.That(ex.ErrorRecord.FullyQualifiedErrorId, Does.StartWith("FailedExit"));
                Assert.That(ex.ErrorRecord.TargetObject, Is.EqualTo(1001));
            });
        }
    }

    [Test]
    public void ConnectService_BindsScopesAndAccessTokenPositionally() {
        var graph = new FakeService("Graph") { ContextValue = null };
        ConnectionRuntime.ServiceResolverOverride = name => name == "Graph" ? graph.Definition : null;

        var result = InvokeScript("Connect-Service Graph Mail.Read -DontConfirm");

        Assert.Multiple(() => {
            Assert.That(result.HadErrors, Is.False);
            Assert.That(graph.ConnectCalls, Is.EqualTo(1));
            Assert.That(graph.LastScopes, Is.EqualTo(new[] { "Mail.Read" }));
        });
    }

    [Test]
    public void ConnectService_DefaultGraphCatalog_InvokesGraphCommands() {
        const string stubs = @"
function global:Connect-MgGraph { param($Scopes, $AccessToken, [switch]$NoWelcome, $ContextScope) $Global:MgConnected = $true; $Global:MgScopes = $Scopes }
function global:Get-MgContext { if (-not $Global:MgConnected) { return }; [pscustomobject]@{ Account = 'graph@example.com'; Scopes = @($Global:MgScopes) } }
function global:Disconnect-MgGraph { $Global:MgConnected = $false }
";

        var result = InvokeScriptWithStubs(stubs, "Connect-Service Graph -DontConfirm");

        Assert.Multiple(() => {
            Assert.That(result.HadErrors, Is.False);
            Assert.That(
                result.Information.Select(i => i.MessageData?.ToString()),
                Does.Contain("Connected to Graph as [graph@example.com]."));
        });
    }

    [Test]
    public void ConnectService_DefaultExchangeCatalog_InvokesExchangeCommands() {
        const string stubs = @"
function global:Connect-ExchangeOnline { param($ShowBanner, $AccessToken) $Global:ExchangeConnected = $true }
function global:Get-ConnectionInformation { param($ConnectionId) [pscustomobject]@{ ConnectionId = 'connection-1'; UserPrincipalName = 'exchange@example.com' } }
function global:Disconnect-ExchangeOnline { param($Confirm) $Global:ExchangeConnected = $false }
";

        var result = InvokeScriptWithStubs(stubs, "Connect-Service ExchangeOnline -DontConfirm");

        Assert.Multiple(() => {
            Assert.That(result.HadErrors, Is.False);
            Assert.That(
                result.Information.Select(i => i.MessageData?.ToString()),
                Does.Contain("Connected to ExchangeOnline as [exchange@example.com]."));
        });
    }

    [Test]
    public void RunCommand_ThrowsWhenCommandWritesNonTerminatingError() {
        using var runspace = CreateRunspace();
        var previous = Runspace.DefaultRunspace;
        Runspace.DefaultRunspace = runspace;

        try {
            var exception = Assert.Throws<InvalidOperationException>(
                () => ConnectionRuntime.RunCommand("Write-Error", ("Message", "boom")));
            Assert.That(exception!.Message, Does.Contain("boom"));
        } finally {
            Runspace.DefaultRunspace = previous;
        }
    }

    [Test]
    public void ConnectService_AlreadyConnectedWithDontConfirm_SkipsConnect() {
        var graph = new FakeService("Graph") {
            ContextValue = "user@example.com",
            IsValid = _ => true,
        };
        ConnectionRuntime.ServiceResolverOverride = name => name == "Graph" ? graph.Definition : null;

        var result = InvokeCommand(
            ("Services", new[] { "Graph" }),
            ("DontConfirm", SwitchParameter.Present));

        Assert.Multiple(() => {
            Assert.That(result.HadErrors, Is.False);
            Assert.That(graph.ConnectCalls, Is.EqualTo(0));
            Assert.That(graph.DisconnectCalls, Is.EqualTo(0));
        });
    }

    [Test]
    public void ConnectService_MultiServiceContextMismatch_DisconnectsAndReconnects() {
        var exchange = new FakeService("ExchangeOnline") { ContextValue = "userA@example.com" };
        var graph = new FakeService("Graph") {
            ContextValue = "userB@example.com",
            ConnectedAccount = "userA@example.com",
        };

        ConnectionRuntime.ServiceResolverOverride = name => name switch {
            "ExchangeOnline" => exchange.Definition,
            "Graph" => graph.Definition,
            _ => null,
        };

        var result = InvokeCommand(
            ("Services", new[] { "ExchangeOnline", "Graph" }),
            ("DontConfirm", SwitchParameter.Present));

        Assert.Multiple(() => {
            Assert.That(result.HadErrors, Is.False);
            Assert.That(graph.DisconnectCalls, Is.EqualTo(1));
            Assert.That(graph.ConnectCalls, Is.EqualTo(1));
        });
    }

    [Test]
    public void ConnectService_AlreadyConnectedMissingScopes_DisconnectsAndReconnects() {
        var graph = new FakeService("Graph") {
            ContextValue = "user@example.com",
            IsValid = _ => false,
        };
        ConnectionRuntime.ServiceResolverOverride = name => name == "Graph" ? graph.Definition : null;

        var result = InvokeCommand(
            ("Services", new[] { "Graph" }),
            ("Scopes", new[] { "Mail.Read" }));

        Assert.Multiple(() => {
            Assert.That(result.HadErrors, Is.False);
            Assert.That(graph.DisconnectCalls, Is.EqualTo(1));
            Assert.That(graph.ConnectCalls, Is.EqualTo(1));
        });
    }

    private static CommandInvocationResult InvokeCommand(params (string Name, object? Value)[] parameters) {
        using var runspace = CreateRunspace();

        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddCommand("Connect-Service");

        foreach (var (name, value) in parameters) {
            powerShell.AddParameter(name, value);
        }

        return Invoke(powerShell);
    }

    private static CommandInvocationResult InvokeScript(string script) {
        using var runspace = CreateRunspace();

        using var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.Runspace = runspace;
        powerShell.AddScript(script);

        return Invoke(powerShell);
    }

    private static CommandInvocationResult InvokeScriptWithStubs(string stubs, string script) {
        using var runspace = CreateRunspace();
        var previous = Runspace.DefaultRunspace;
        Runspace.DefaultRunspace = runspace;

        try {
            using var powerShell = System.Management.Automation.PowerShell.Create();
            powerShell.Runspace = runspace;
            powerShell.AddScript(stubs + Environment.NewLine + script);
            return Invoke(powerShell);
        } finally {
            Runspace.DefaultRunspace = previous;
        }
    }

    private static Runspace CreateRunspace() {
        var initialSessionState = InitialSessionState.CreateDefault2();
        initialSessionState.Commands.Add(
            new SessionStateCmdletEntry("Connect-Service", typeof(ConnectServiceCommand), helpFileName: null));

        var runspace = RunspaceFactory.CreateRunspace(initialSessionState);
        runspace.Open();
        return runspace;
    }

    private static CommandInvocationResult Invoke(System.Management.Automation.PowerShell powerShell) {
        var output = new Collection<PSObject>();
        powerShell.Invoke(input: null, output);
        return new CommandInvocationResult(
            output,
            [.. powerShell.Streams.Information],
            [.. powerShell.Streams.Error],
            powerShell.HadErrors);
    }

    private sealed record CommandInvocationResult(
        Collection<PSObject> Output,
        IReadOnlyList<InformationRecord> Information,
        IReadOnlyList<ErrorRecord> Errors,
        bool HadErrors);

    private sealed class FakeService {
        internal FakeService(string name) {
            this.Name = name;
            this.Definition = new ServiceDefinition(
                name,
                context: () => this.ContextValue,
                connect: (scopes, _) => {
                    this.ConnectCalls++;
                    this.LastScopes = scopes;
                    if (this.ConnectThrows is not null) {
                        throw this.ConnectThrows;
                    }

                    this.ContextValue = this.ConnectedAccount ?? name + "@example.com";
                },
                disconnect: () => {
                    this.DisconnectCalls++;
                    if (this.DisconnectThrows is not null) {
                        throw this.DisconnectThrows;
                    }

                    this.ContextValue = null;
                },
                isValid: scopes => this.IsValid?.Invoke(scopes),
                matchable: true);
        }

        internal string Name { get; }

        internal string? ContextValue { get; set; }

        internal string? ConnectedAccount { get; set; }

        internal Func<string[]?, bool?>? IsValid { get; set; }

        internal Exception? ConnectThrows { get; set; }

        internal Exception? DisconnectThrows { get; set; }

        internal string[]? LastScopes { get; private set; }

        internal int ConnectCalls { get; private set; }

        internal int DisconnectCalls { get; private set; }

        internal ServiceDefinition Definition { get; }
    }
}
