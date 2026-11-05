// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Text;
using AMT.PowerShell.Common.Commands.Utils;

namespace AMT.PowerShell.Common.Tests.Commands.Utils;

[TestFixture]
[NonParallelizable]
public sealed class UtilsCommandTests {
    [TearDown]
    public void TearDown() {
        InstallModuleFromGitHubOperations.InstallOverride = null;
        NetworkConnectionOperations.NetworkConnectionProbeOverride = null;
    }

    [Test]
    public void ConvertToInvokableValue_ParityCases_RoundTrip() {
        using var runspace = CreateRunspace();

        AssertRoundTrip(runspace, null, "$null");
        AssertRoundTrip(runspace, true, "$True");
        AssertRoundTrip(runspace, false, "$False");
        AssertRoundTrip(runspace, "Hello, World!", "\"Hello, World!\"");
        AssertRoundTrip(runspace, 123, "123");

        var arrayExpr = InvokeCommand(runspace, "ConvertTo-InvokableValue", ("Value", new object[] { 1, 2, 3 }));
        Assert.That((string)arrayExpr[0].BaseObject, Is.EqualTo("@(1, 2, 3)"));

        var hashtableExpr = InvokeCommand(runspace, "ConvertTo-InvokableValue", ("Value", new Hashtable { ["Key"] = "Value" }));
        Assert.That((string)hashtableExpr[0].BaseObject, Is.EqualTo("@{Key = \"Value\"}"));

        var objectExpr = InvokeScript(
            runspace,
            "$o = [PSCustomObject]@{ Name = 'AMT'; Count = 1 }; ConvertTo-InvokableValue -Value $o");

        var objectResult = (string)objectExpr[0].BaseObject;
        Assert.That(objectResult, Does.StartWith("[PSCustomObject]@{"));

        var nested = new Hashtable { ["OuterKey"] = new Hashtable { ["InnerKey"] = "InnerValue" } };
        var nestedExpr = (string)InvokeCommand(runspace, "ConvertTo-InvokableValue", ("Value", nested))[0].BaseObject;
        var nestedRoundTrip = InvokeExpression(runspace, nestedExpr);

        Assert.That(nestedRoundTrip, Has.Count.EqualTo(1));
        Assert.That(nestedRoundTrip[0].BaseObject, Is.TypeOf<Hashtable>());
    }

    [Test]
    public void ConvertToInvokableValue_RoundTrips_PowerShellSensitiveCharacters() {
        using var runspace = CreateRunspace();

        const string value = "Path C:\\temp\\file.txt\nDollar $name and backtick ` marker";

        var expressionResults = InvokeCommand(runspace, "ConvertTo-InvokableValue", ("Value", value));
        var expression = (string)expressionResults[0].BaseObject;

        var roundTrip = InvokeExpression(runspace, expression);

        Assert.That(roundTrip, Has.Count.EqualTo(1));
        Assert.That(roundTrip[0].BaseObject, Is.EqualTo(value));
    }

    [Test]
    public void RemoveEncodingBomAndGetContentEncoding_BehaviorParity() {
        using var runspace = CreateRunspace();

        var utf8Bom = new UTF8Encoding(true).GetPreamble();
        var payload = Encoding.UTF8.GetBytes("Hello, World!");
        var bytes = utf8Bom.Concat(payload).ToArray();

        var removed = InvokeCommand(
            runspace,
            "Remove-EncodingBom",
            ("Bytes", bytes),
            ("Encoding", new UTF8Encoding(true)));

        Assert.That((byte[])removed[0].BaseObject, Is.EqualTo(payload));

        var detected = InvokeCommand(runspace, "Get-ContentEncoding", ("ContentBytes", bytes));
        Assert.That(((Encoding)detected[0].BaseObject).WebName, Is.EqualTo("utf-8"));

        var path = Path.Combine(Path.GetTempPath(), $"enc-{Guid.NewGuid():N}.txt");
        try {
            File.WriteAllBytes(path, bytes);
            var byPath = InvokeCommand(runspace, "Get-ContentEncoding", ("Path", path));
            Assert.That(((Encoding)byPath[0].BaseObject).WebName, Is.EqualTo("utf-8"));
        } finally {
            TryDelete(path);
        }
    }

    [Test]
    public void ReturnTypeAndParametersHelpers_RepresentativeBehavior() {
        using var runspace = CreateRunspace();

        var scriptBlock = ScriptBlock.Create("param([string]$Name) return \"ok\"");

        var returnTypes = InvokeCommand(runspace, "Get-ReturnType", ("InputObject", scriptBlock));
        Assert.That(returnTypes, Has.Count.EqualTo(1));
        Assert.That(returnTypes[0].BaseObject, Is.EqualTo(typeof(string)));

        var validReturn = InvokeCommand(
            runspace,
            "Test-ReturnType",
            ("InputObject", scriptBlock),
            ("ValidTypes", new[] { typeof(string) }));
        Assert.That((bool)validReturn[0].BaseObject, Is.True);

        var invalidReturn = InvokeCommand(
            runspace,
            "Test-ReturnType",
            ("InputObject", scriptBlock),
            ("ValidTypes", new[] { typeof(int) }));
        Assert.That((bool)invalidReturn[0].BaseObject, Is.False);

        var allowNull = InvokeCommand(
            runspace,
            "Test-ReturnType",
            ("InputObject", ScriptBlock.Create("return $null")),
            ("ValidTypes", new[] { typeof(string) }),
            ("AllowNull", true));
        Assert.That((bool)allowNull[0].BaseObject, Is.True);

        var validParams = InvokeCommand(
            runspace,
            "Test-Parameters",
            ("InputObject", scriptBlock),
            ("ValidTypes", new[] { "String" }));
        Assert.That((bool)validParams[0].BaseObject, Is.True);

        var invalidParams = InvokeCommand(
            runspace,
            "Test-Parameters",
            ("InputObject", scriptBlock),
            ("ValidTypes", new[] { "Int32" }));
        Assert.That((bool)invalidParams[0].BaseObject, Is.False);
    }

    [Test]
    public void GetVarOrSave_UsesEnvVarAndValidationPath() {
        using var runspace = CreateRunspace();

        var variableName = $"AMT_UTILS_TEST_{Guid.NewGuid():N}";

        try {
            Environment.SetEnvironmentVariable(variableName, "existing", EnvironmentVariableTarget.Process);

            var fromEnv = InvokeCommand(
                runspace,
                "Get-VarOrSave",
                ("VariableName", variableName),
                ("LazyValue", ScriptBlock.Create("return 'lazy'")),
                ("Validate", ScriptBlock.Create("param($v) return $v -eq 'existing'")));

            Assert.That((string)fromEnv[0].BaseObject, Is.EqualTo("existing"));

            Environment.SetEnvironmentVariable(variableName, "bad", EnvironmentVariableTarget.Process);

            var fromLazy = InvokeCommand(
                runspace,
                "Get-VarOrSave",
                ("VariableName", variableName),
                ("LazyValue", ScriptBlock.Create("return 'fixed'")),
                ("Validate", ScriptBlock.Create("param($v) return $v -eq 'fixed'")));

            Assert.That((string)fromLazy[0].BaseObject, Is.EqualTo("fixed"));
            Assert.That(Environment.GetEnvironmentVariable(variableName), Is.EqualTo("fixed"));
        } finally {
            Environment.SetEnvironmentVariable(variableName, null, EnvironmentVariableTarget.Process);
        }
    }

    [Test]
    public void ModuleImport_IsClean_And_Idempotent() {
        using var runspace = CreateImportedModuleRunspace();

        var modulePath = EscapePathForSingleQuotedString(GetModuleAssemblyPath());
        var script = $"Import-Module '{modulePath}' -Force -ErrorAction Stop; "
            + $"Import-Module '{modulePath}' -Force -ErrorAction Stop; 'ok'";

        var result = InvokeScript(runspace, script);

        Assert.That(result, Has.Count.EqualTo(1));
        Assert.That(result[0].BaseObject, Is.EqualTo("ok"));
    }

    [Test]
    public void ModuleImport_ExposesAliases_And_AliasFlowWorks() {
        using var runspace = CreateImportedModuleRunspace();

        var aliasNames = InvokeScript(runspace, "(Get-Alias await).Name; (Get-Alias async).Name; (Get-Alias lazy).Name");
        Assert.That(aliasNames.Select(o => o.BaseObject.ToString()), Is.EqualTo(new[] { "await", "async", "lazy" }));

        var asyncResult = InvokeScript(runspace, "$run = async { return 42 }; await $run");
        Assert.That(asyncResult, Has.Count.EqualTo(1));
        Assert.That(asyncResult[0].BaseObject, Is.EqualTo(42));

        var lazyVariableResult = InvokeScript(runspace, "lazy -Name Value -Value { return 9 } | Out-Null; (& $Value)");
        Assert.That(lazyVariableResult, Has.Count.EqualTo(1));
        Assert.That(lazyVariableResult[0].BaseObject, Is.EqualTo(9));

        var lazyPropertyResult = InvokeScript(
            runspace,
            "$o = [pscustomobject]@{}; $o | Add-LazyProperty -Name TestValue -Value { 'ok' } | Out-Null; $o.TestValue");
        Assert.That(lazyPropertyResult, Has.Count.EqualTo(1));
        Assert.That(lazyPropertyResult[0].BaseObject, Is.EqualTo("ok"));
    }

    [Test]
    public void ETagAndCompareFileHashToS3ETag_DeterministicParity() {
        using var runspace = CreateRunspace();

        var path = Path.Combine(Path.GetTempPath(), $"etag-{Guid.NewGuid():N}.txt");

        try {
            File.WriteAllText(path, "hello world", Encoding.UTF8);

            var etagResults = InvokeCommand(runspace, "Get-ETag", ("Path", path), ("ChunkSize", 1024));
            Assert.That(etagResults, Has.Count.EqualTo(1));

            var etag = (string)etagResults[0].BaseObject;
            var compareResults = InvokeCommand(runspace, "Compare-FileHashToS3ETag", ("Path", path), ("ETag", etag));

            Assert.That(compareResults, Has.Count.EqualTo(1));
            Assert.That((bool)compareResults[0].BaseObject, Is.True);
        } finally {
            TryDelete(path);
        }
    }

    [Test]
    public void InstallModuleFromGitHub_UsesDeterministicTestSeam() {
        using var runspace = CreateRunspace();

        string? capturedRepo = null;
        string? capturedBranch = null;
        string? capturedScope = null;

        InstallModuleFromGitHubOperations.InstallOverride = request => {
            capturedRepo = request.GitHubRepo;
            capturedBranch = request.Branch;
            capturedScope = request.Scope;
            return "SeamModule";
        };

        var results = InvokeCommand(
            runspace,
            "Install-ModuleFromGitHub",
            ("GitHubRepo", "owner/repo"),
            ("Branch", "main"),
            ("Scope", "CurrentUser"));

        Assert.Multiple(() => {
            Assert.That(results, Has.Count.EqualTo(1));
            Assert.That((string)results[0].BaseObject, Is.EqualTo("SeamModule"));
            Assert.That(capturedRepo, Is.EqualTo("owner/repo"));
            Assert.That(capturedBranch, Is.EqualTo("main"));
            Assert.That(capturedScope, Is.EqualTo("CurrentUser"));
        });
    }

    [Test]
    public void TestNetworkConnection_UsesDeterministicProbeSeam() {
        using var runspace = CreateRunspace();

        NetworkConnectionOperations.NetworkConnectionProbeOverride = () => true;
        var yes = InvokeCommand(runspace, "Test-NetworkConnection");
        Assert.That((bool)yes[0].BaseObject, Is.True);

        NetworkConnectionOperations.NetworkConnectionProbeOverride = () => false;
        var no = InvokeCommand(runspace, "Test-NetworkConnection");
        Assert.That((bool)no[0].BaseObject, Is.False);
    }

    private static void AssertRoundTrip(Runspace runspace, object? value, string expectedExpression) {
        var expressionResults = InvokeCommand(runspace, "ConvertTo-InvokableValue", ("Value", value));
        Assert.That(expressionResults, Has.Count.EqualTo(1));

        var expression = (string)expressionResults[0].BaseObject;
        Assert.That(expression, Is.EqualTo(expectedExpression));

        var roundTrip = InvokeExpression(runspace, expression);

        if (value is null) {
            var isNullRoundTrip = roundTrip.Count == 0
                || (roundTrip.Count == 1 && (roundTrip[0] is null || roundTrip[0].BaseObject is null));
            Assert.That(isNullRoundTrip, Is.True);
            return;
        }

        Assert.That(roundTrip, Has.Count.EqualTo(1));
        Assert.That(roundTrip[0].BaseObject, Is.EqualTo(value));
    }

    private static Runspace CreateRunspace() {
        var iss = InitialSessionState.CreateDefault2();

        iss.Commands.Add(new SessionStateCmdletEntry("ConvertTo-InvokableValue", typeof(ConvertToInvokableValueCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Remove-EncodingBom", typeof(RemoveEncodingBomCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Get-ContentEncoding", typeof(GetContentEncodingCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Get-VarOrSave", typeof(GetVarOrSaveCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Get-Ast", typeof(GetAstCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Get-ReturnType", typeof(GetReturnTypeCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Test-ReturnType", typeof(TestReturnTypeCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Test-Parameters", typeof(TestParametersCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Install-ModuleFromGitHub", typeof(InstallModuleFromGitHubCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Test-NetworkConnection", typeof(TestNetworkConnectionCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Wait-Task", typeof(WaitTaskCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Start-AsyncTask", typeof(StartAsyncTaskCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Add-LazyProperty", typeof(AddLazyPropertyCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Set-LazyVariable", typeof(SetLazyVariableCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Test-IsRunningAsSystem", typeof(TestIsRunningAsSystemCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Test-IsWindows11", typeof(TestIsWindows11Command), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Compare-FileHashToS3ETag", typeof(CompareFileHashToS3EtagCommand), null));
        iss.Commands.Add(new SessionStateCmdletEntry("Get-ETag", typeof(GetEtagCommand), null));

        var runspace = RunspaceFactory.CreateRunspace(iss);
        runspace.Open();
        return runspace;
    }

    private static Runspace CreateImportedModuleRunspace() {
        var runspace = RunspaceFactory.CreateRunspace(InitialSessionState.CreateDefault2());
        runspace.Open();

        var importScript = $"Import-Module '{EscapePathForSingleQuotedString(GetModuleAssemblyPath())}' -Force -ErrorAction Stop";
        InvokeScript(runspace, importScript);

        return runspace;
    }

    private static string GetModuleAssemblyPath() =>
        typeof(ConvertToInvokableValueCommand).Assembly.Location;

    private static string EscapePathForSingleQuotedString(string path) =>
        path.Replace("'", "''", StringComparison.Ordinal);

    private static Collection<PSObject> InvokeCommand(
            Runspace runspace,
            string command,
            params (string Name, object? Value)[] parameters) {
        using var ps = System.Management.Automation.PowerShell.Create();
        ps.Runspace = runspace;
        ps.AddCommand(command);

        foreach (var (name, value) in parameters) {
            ps.AddParameter(name, value);
        }

        var output = ps.Invoke();

        if (ps.HadErrors) {
            var errors = string.Join(Environment.NewLine, ps.Streams.Error.Select(e => e.ToString()));
            throw new AssertionException($"Command '{command}' failed:{Environment.NewLine}{errors}");
        }

        return output;
    }

    private static Collection<PSObject> InvokeExpression(Runspace runspace, string expression) {
        using var ps = System.Management.Automation.PowerShell.Create();
        ps.Runspace = runspace;
        ps.AddCommand("Invoke-Expression");
        ps.AddParameter("Command", expression);

        var output = ps.Invoke();

        if (ps.HadErrors) {
            var errors = string.Join(Environment.NewLine, ps.Streams.Error.Select(e => e.ToString()));
            throw new AssertionException($"Expression '{expression}' failed:{Environment.NewLine}{errors}");
        }

        return output;
    }

    private static Collection<PSObject> InvokeScript(Runspace runspace, string script) {
        using var ps = System.Management.Automation.PowerShell.Create();
        ps.Runspace = runspace;
        ps.AddScript(script);

        var output = ps.Invoke();

        if (ps.HadErrors) {
            var errors = string.Join(Environment.NewLine, ps.Streams.Error.Select(e => e.ToString()));
            throw new AssertionException($"Script failed:{Environment.NewLine}{errors}");
        }

        return output;
    }

    private static void TryDelete(string path) {
        try {
            if (File.Exists(path)) {
                File.Delete(path);
            }
        } catch {
        }
    }
}
