// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Globalization;
using System.Management.Automation;
using System.Security;
using AMT.PowerShell.Common.Commands.Exit;
using AMT.PowerShell.Common.Commands.Input;

namespace AMT.PowerShell.Common.Commands.Connection;

/// <summary>Establish authenticated connections to one or more Microsoft cloud services.</summary>
/// <remarks>
/// <para>Iterates over each service in <c>Services</c>, resolving its <see cref="ServiceDefinition"/>
/// from <see cref="ConnectionRuntime"/>. For each service the cmdlet:</para>
/// <para>1. Checks whether an existing connection is already present and optionally re-uses it,
/// prompting for confirmation unless <c>DontConfirm</c> is set.</para>
/// <para>2. Disconnects and reconnects when the existing connection is missing required <c>Scopes</c>
/// or when multiple services are connected under different accounts.</para>
/// <para>3. Verifies after connecting that all services share the same account identity when
/// their definitions are marked as matchable.</para>
/// <para>When <c>CheckOnly</c> is set the cmdlet only verifies connectivity and throws a
/// terminating error for any service that is not already connected.</para>
/// </remarks>
/// <example>
/// <code>Connect-Service -Services ExchangeOnline, Graph -Scopes 'Mail.Read' -DontConfirm</code>
/// Connects to Exchange Online and Microsoft Graph, skipping the confirmation prompt.
/// </example>
/// <example>
/// <code>Connect-Service -Services Graph -CheckOnly</code>
/// Throws a terminating error when not already connected to Microsoft Graph.
/// </example>
[Cmdlet("Connect", "Service")]
public sealed class ConnectServiceCommand : PSCmdlet {
    private const string CantDisconnectDescription = "Failed to disconnect from {0}.";
    private const string NotConnectedDescription = "Not connected to {0}, must be connected to continue.";
    private const string CouldNotConnectDescription = "Failed to connect to {0}.";
    private const string NotMatchingAccountsDescription =
        "Not all services are connected with the same account, please ensure all services are connected with the same account.";

    private static readonly string[] ConfirmationChoices = ["Yes", "No"];

    private int _cantDisconnectCode;
    private int _notConnectedCode;
    private int _couldNotConnectCode;

    /// <summary>One or more service names to connect to; accepted values are <c>ExchangeOnline</c>, <c>SecurityCompliance</c>, and <c>Graph</c>.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [Alias("Service")]
    [ValidateSet(
        ConnectionRuntime.ExchangeOnline,
        ConnectionRuntime.SecurityCompliance,
        ConnectionRuntime.Graph)]
    public string[] Services { get; set; } = [];

    /// <summary>Permission scopes to request when connecting; primarily used for Microsoft Graph.</summary>
    [Parameter(Position = 1)]
    public string[]? Scopes { get; set; }

    /// <summary>Pre-acquired access token for token-based authentication; bypasses the interactive login flow when provided.</summary>
    [Parameter(Position = 2)]
    public SecureString? AccessToken { get; set; }

    /// <summary>When present, skips the interactive confirmation prompt when a service is already connected.</summary>
    [Parameter]
    public SwitchParameter DontConfirm { get; set; }

    /// <summary>When present, only verifies that each service is connected and throws a terminating error for any that are not.</summary>
    [Parameter]
    public SwitchParameter CheckOnly { get; set; }

    protected override void ProcessRecord() {
        this.RegisterExitCodes();

        ServiceDefinition? last = null;
        string? account = null;

        foreach (var service in this.Services) {
            var definition = ConnectionRuntime.Resolve(service);
            if (definition is null) {
                this.ThrowNotConnected(service);
                continue;
            }

            var context = TryGetContext(definition);

            if (last is not null && !CanShareContext(definition, last)) {
                this.WriteInformation("Not all services are connected with the same account, forcing disconnect...", Array.Empty<string>());
                this.Disconnect(definition);
            } else if (context is not null) {
                var isValid = definition.IsValid?.Invoke(this.Scopes);
                if (isValid == false) {
                    this.WriteInformation($"Connected to {service}, but missing required scopes. Disconnecting...", Array.Empty<string>());
                    this.Disconnect(definition);
                    if (this.CheckOnly.IsPresent) {
                        this.ThrowNotConnected(service);
                        continue;
                    }
                } else if (!this.DontConfirm.IsPresent) {
                    if (this.ConfirmContinue($"Already connected to {service} as [{context}]")) {
                        this.WriteVerbose("Continuing with current connection...");
                        account = context;
                        last = definition;
                        continue;
                    }

                    this.Disconnect(definition);
                    if (this.CheckOnly.IsPresent) {
                        this.ThrowNotConnected(service);
                        continue;
                    }
                } else {
                    this.WriteVerbose($"Already connected to {service}. Skipping...");
                    account = context;
                    last = definition;
                    continue;
                }
            } else if (this.CheckOnly.IsPresent) {
                this.ThrowNotConnected(service);
                continue;
            }

            if (this.CheckOnly.IsPresent) {
                continue;
            }

            while (true) {
                try {
                    if (this.AccessToken is not null) {
                        this.WriteInformation($"Connecting to {service} with access token...", Array.Empty<string>());
                    } else {
                        this.WriteInformation($"Connecting to {service}...", Array.Empty<string>());
                    }

                    this.WriteVerbose($"Scopes: {string.Join(", ", this.Scopes ?? Array.Empty<string>())}");
                    definition.Connect(this.Scopes, this.AccessToken);
                } catch (Exception ex) {
                    this.ThrowCouldNotConnect(service, ex);
                }

                if (last is not null) {
                    this.WriteInformation("Checking if all services are connected with the same account...", Array.Empty<string>());
                    this.WriteInformation($"Service A: {service}", Array.Empty<string>());
                    this.WriteInformation($"Service B: {last.Name}", Array.Empty<string>());

                    if (account is not null && !CanShareContext(definition, last)) {
                        this.WriteWarning("Not all services are connected with the same account, please reconnect with the same account.");
                        this.Disconnect(definition);
                        continue;
                    }
                }

                if (account is null && definition.Matchable) {
                    account = TryGetContext(definition);
                }

                this.WriteInformation($"Connected to {service} as [{account}].", Array.Empty<string>());
                break;
            }
        }
    }

    private bool ConfirmContinue(string title) {
        if (ConnectionRuntime.ConfirmationOverride is not null) {
            return ConnectionRuntime.ConfirmationOverride(this, title, "Do you want to continue?");
        }

        var selection = InputOperations.ReadSelection(
            this,
            title,
            "Do you want to continue?",
            ConfirmationChoices,
            defaultChoice: 0);

        if (selection.IsCanceled) {
            throw new PipelineStoppedException();
        }

        var value = (selection.Value ?? string.Empty).Trim();
        if (value.Length == 0) {
            value = ConfirmationChoices[0];
        }

        return string.Equals(value, "Yes", StringComparison.OrdinalIgnoreCase);
    }

    private void RegisterExitCodes() {
        var runspace = ExitStore.RequireRunspace();

        // Register in legacy order so assigned codes stay stable.
        this._cantDisconnectCode = ExitStore.RegisterExitCode(runspace, CantDisconnectDescription);
        this._notConnectedCode = ExitStore.RegisterExitCode(runspace, NotConnectedDescription);
        this._couldNotConnectCode = ExitStore.RegisterExitCode(runspace, CouldNotConnectDescription);
        _ = ExitStore.RegisterExitCode(runspace, NotMatchingAccountsDescription);
    }

    private void Disconnect(ServiceDefinition definition) {
        try {
            definition.Disconnect();
        } catch (Exception ex) {
            this.Fail(this._cantDisconnectCode, definition.Name, ex);
        }
    }

    private void ThrowNotConnected(string service) =>
        this.Fail(this._notConnectedCode, service);

    private void ThrowCouldNotConnect(string service, Exception exception) =>
        this.Fail(this._couldNotConnectCode, service, exception);

    // Mirrors Invoke-FailedExit: display the registered description, run failure
    // handlers, then raise a FailedExit error so Invoke-RunMain sets LASTEXITCODE.
    private void Fail(int exitCode, string service, Exception? exception = null) {
        var runspace = ExitStore.RequireRunspace();
        var description = ExitStore.GetDescription(runspace, exitCode);
        var message = string.IsNullOrEmpty(description)
            ? $"Exit code {exitCode}"
            : string.Format(CultureInfo.InvariantCulture, description!, service);

        this.WriteInformation("❌ " + message, new[] { "AMT.ErrorDisplay" });
        ExitHandlerRunner.Invoke(runspace, true, this.WriteDebug, this.WriteWarning);

        var error = exception is null
            ? new Exception(message)
            : new InvalidOperationException(message, exception);

        this.ThrowTerminatingError(new ErrorRecord(
            error,
            "FailedExit",
            ErrorCategory.ConnectionError,
            exitCode));
    }

    private static string? TryGetContext(ServiceDefinition definition) {
        try {
            return definition.Context();
        } catch {
            return null;
        }
    }

    private static bool CanShareContext(ServiceDefinition a, ServiceDefinition b) =>
        !IsMatchable(a, b) || SameContext(a, b);

    private static bool IsMatchable(ServiceDefinition a, ServiceDefinition b) =>
        a.Matchable && b.Matchable;

    private static bool SameContext(ServiceDefinition a, ServiceDefinition b) {
        var contextA = TryGetContext(a);
        var contextB = TryGetContext(b);
        return !string.IsNullOrEmpty(contextA)
            && !string.IsNullOrEmpty(contextB)
            && string.Equals(contextA, contextB, StringComparison.OrdinalIgnoreCase);
    }
}
