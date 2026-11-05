// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Runtime.CompilerServices;
using System.Security;

namespace AMT.PowerShell.Common.Commands.Connection;

// Static registry of connectable services plus the seams that keep Connect-Service
// deterministic. The default catalog invokes the external Graph/Exchange cmdlets;
// tests inject fakes through ServiceResolverOverride.
internal static class ConnectionRuntime {
    internal const string ExchangeOnline = "ExchangeOnline";
    internal const string SecurityCompliance = "SecurityComplience";
    internal const string Graph = "Graph";

    internal static Func<string, ServiceDefinition?>? ServiceResolverOverride { get; set; }

    internal static Func<PSCmdlet, string, string, bool>? ConfirmationOverride { get; set; }

    private static readonly ConditionalWeakTable<Runspace, SessionState> SessionStates = new();

    internal static ServiceDefinition? Resolve(string service) {
        if (ServiceResolverOverride is not null) {
            return ServiceResolverOverride(service);
        }

        return DefaultCatalog.TryGetValue(service, out var definition) ? definition : null;
    }

    internal static IReadOnlyDictionary<string, ServiceDefinition> DefaultCatalog { get; } =
        BuildDefaultCatalog();

    private static Dictionary<string, ServiceDefinition> BuildDefaultCatalog() =>
        new(StringComparer.OrdinalIgnoreCase) {
            [ExchangeOnline] = new ServiceDefinition(
                ExchangeOnline,
                context: () => ReadSessionUserPrincipal(ExchangeOnline),
                connect: (_, accessToken) => {
                    if (accessToken is not null) {
                        RunCommand("Connect-ExchangeOnline", ("ShowBanner", false), ("AccessToken", accessToken));
                    } else {
                        RunCommand("Connect-ExchangeOnline", ("ShowBanner", false));
                    }

                    StoreSessionId(ExchangeOnline, ReadLatestConnectionId());
                },
                disconnect: () => RunCommand("Disconnect-ExchangeOnline", ("Confirm", false))),
            [SecurityCompliance] = new ServiceDefinition(
                SecurityCompliance,
                context: () => ReadSessionUserPrincipal(SecurityCompliance),
                connect: (_, _) => {
                    RunCommand("Connect-IPPSSession", ("ShowBanner", false));
                    StoreSessionId(SecurityCompliance, ReadLatestConnectionId());
                },
                disconnect: () => RunCommand("Disconnect-ExchangeOnline", ("Confirm", false))),
            [Graph] = new ServiceDefinition(
                Graph,
                context: () => RunScalar("try { Get-MgContext | Select-Object -ExpandProperty Account } catch { $null }"),
                connect: ConnectGraph,
                disconnect: () => RunCommand("Disconnect-MgGraph"),
                isValid: GraphIsValid),
        };

    private static void ConnectGraph(string[]? scopes, SecureString? accessToken) {
        if (accessToken is not null) {
            RunCommand(
                "Connect-MgGraph",
                ("AccessToken", accessToken),
                ("NoWelcome", SwitchParameter.Present),
                ("ContextScope", "Process"));

            var contextScopes = RunStringArray("Get-MgContext | Select-Object -ExpandProperty Scopes");
            if (scopes is { Length: > 0 }) {
                var missing = scopes
                    .Where(scope => !contextScopes.Contains(scope, StringComparer.OrdinalIgnoreCase))
                    .ToArray();
                if (missing.Length > 0) {
                    RunCommand("Disconnect-MgGraph");
                }
            }
        }

        if (!HasGraphContext()) {
            RunCommand(
                "Connect-MgGraph",
                ("Scopes", scopes),
                ("NoWelcome", SwitchParameter.Present),
                ("ContextScope", "Process"));
        }
    }

    private static bool? GraphIsValid(string[]? scopes) =>
        RunPredicate(
            "param($Scopes) try { $C = Get-MgContext } catch { return $false } "
            + "if ($Scopes) { ($Scopes | Where-Object { $C.Scopes -notcontains $_ }).Count -eq 0 } "
            + "else { $true }",
            scopes ?? Array.Empty<string>());

    private static bool HasGraphContext() =>
        !string.IsNullOrEmpty(RunScalar("try { Get-MgContext | Select-Object -ExpandProperty Account } catch { $null }"));

    private static string? ReadSessionUserPrincipal(string service) {
        var sessionId = service == ExchangeOnline
            ? GetSessionState().ExchangeSessionId
            : GetSessionState().IppSessionId;

        if (string.IsNullOrEmpty(sessionId)) {
            return null;
        }

        var escaped = sessionId!.Replace("'", "''");
        return RunScalar(
            $"Get-ConnectionInformation -ConnectionId '{escaped}' "
            + "| Select-Object -ExpandProperty UserPrincipalName");
    }

    private static string? ReadLatestConnectionId() =>
        RunScalar("Get-ConnectionInformation | Select-Object -Last 1 -ExpandProperty ConnectionId");

    private static void StoreSessionId(string service, string? sessionId) {
        var state = GetSessionState();
        if (service == ExchangeOnline) {
            state.ExchangeSessionId = sessionId;
        } else {
            state.IppSessionId = sessionId;
        }
    }

    private static SessionState GetSessionState() {
        var runspace = Runspace.DefaultRunspace ?? throw new InvalidOperationException("No active runspace.");
        return SessionStates.GetValue(runspace, _ => new SessionState());
    }

    internal static void RunCommand(string command, params (string Name, object? Value)[] parameters) {
        using var powerShell = System.Management.Automation.PowerShell.Create(RunspaceMode.CurrentRunspace);
        powerShell.AddCommand(command);
        foreach (var (name, value) in parameters) {
            if (value is not null) {
                powerShell.AddParameter(name, value);
            }
        }

        _ = powerShell.Invoke();
        if (!powerShell.HadErrors) {
            return;
        }

        var errors = powerShell.Streams.Error;
        var message = errors.Count > 0 && !string.IsNullOrWhiteSpace(errors[0].Exception?.Message)
            ? errors[0].Exception!.Message
            : $"Command '{command}' failed.";

        throw new InvalidOperationException(message, errors.Count > 0 ? errors[0].Exception : null);
    }

    private static string? RunScalar(string script) {
        using var powerShell = System.Management.Automation.PowerShell.Create(RunspaceMode.CurrentRunspace);
        powerShell.AddScript(script);
        var results = powerShell.Invoke();
        if (powerShell.HadErrors || results.Count == 0) {
            return null;
        }

        return results[results.Count - 1]?.ToString();
    }

    private static bool RunPredicate(string script, params object?[] arguments) {
        using var powerShell = System.Management.Automation.PowerShell.Create(RunspaceMode.CurrentRunspace);
        powerShell.AddScript(script);
        foreach (var argument in arguments) {
            powerShell.AddArgument(argument);
        }

        var results = powerShell.Invoke();
        if (powerShell.HadErrors || results.Count == 0) {
            return false;
        }

        return LanguagePrimitives.IsTrue(results[results.Count - 1]);
    }

    private static string[] RunStringArray(string script) {
        using var powerShell = System.Management.Automation.PowerShell.Create(RunspaceMode.CurrentRunspace);
        powerShell.AddScript(script);
        var results = powerShell.Invoke();
        if (powerShell.HadErrors) {
            return Array.Empty<string>();
        }

        var values = new List<string>();
        foreach (var result in results) {
            if (result?.BaseObject is string value) {
                values.Add(value);
            }
        }

        return values.ToArray();
    }

    private sealed class SessionState {
        internal string? ExchangeSessionId;
        internal string? IppSessionId;
    }
}
