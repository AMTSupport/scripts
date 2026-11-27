// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Language;

using System.Net.Http;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace AMT.PowerShell.Common.Commands.Utils;

internal sealed class AsyncTaskRun {
    internal AsyncTaskRun(object? input, System.Management.Automation.PowerShell powerShell, IAsyncResult job) {
        Input = input;
        PowerShell = powerShell;
        Job = job;
    }

    public object? Input { get; }

    public IAsyncResult Job { get; }

    internal System.Management.Automation.PowerShell PowerShell { get; }

    public object? Result { get; set; }
}

internal sealed class InstallModuleRequest {
    public string GitHubRepo { get; set; } = string.Empty;

    public string Branch { get; set; } = string.Empty;

    public string Scope { get; set; } = string.Empty;
}

internal static class InstallModuleFromGitHubOperations {
    internal static Func<InstallModuleRequest, string>? InstallOverride { get; set; }

    internal static string Install(InstallModuleRequest request, PSCmdlet cmdlet) {
        if (InstallOverride is not null) {
            return InstallOverride(request);
        }

        var moduleRepoName = request.GitHubRepo.Split('/').LastOrDefault();
        if (string.IsNullOrWhiteSpace(moduleRepoName)) {
            throw new PSArgumentException("GitHubRepo must be in the format 'owner/repo'.", nameof(request.GitHubRepo));
        }

        var zipUrl = $"https://api.github.com/repos/{request.GitHubRepo}/zipball/{request.Branch}";
        var tempDir = Path.GetTempPath();
        var zipPath = Path.Combine(tempDir, $"{moduleRepoName}-{Guid.NewGuid():N}.zip");
        var extractDir = Path.Combine(tempDir, $"{moduleRepoName}-{Guid.NewGuid():N}");

        try {
            DownloadArchive(zipUrl, zipPath);
            ZipFile.ExtractToDirectory(zipPath, extractDir);

            var manifests = Directory.GetFiles(extractDir, "*.psd1", SearchOption.AllDirectories);
            if (manifests.Length == 0) {
                throw new ItemNotFoundException($"No module manifest found in archive '{zipUrl}'.");
            }

            var manifestPath = manifests.Length == 1
                ? manifests[0]
                : manifests.FirstOrDefault(path =>
                    Path.GetFileName(path).StartsWith(moduleRepoName, StringComparison.OrdinalIgnoreCase))
                  ?? manifests[0];

            var moduleName = Path.GetFileNameWithoutExtension(manifestPath);
            var moduleVersion = ParseModuleVersion(manifestPath) ?? "0.0.0";

            var sourceDirectory = Path.GetDirectoryName(manifestPath)
                ?? throw new InvalidOperationException("Failed to resolve module source directory.");

            var moduleRoot = ResolveModuleRoot(request.Scope);
            var targetDirectory = Path.Combine(moduleRoot, moduleName, moduleVersion);

            Directory.CreateDirectory(targetDirectory);
            CopyDirectoryContents(sourceDirectory, targetDirectory);

            cmdlet.WriteVerbose($"Installed module '{moduleName}' to '{targetDirectory}'.");
            return moduleName;
        } finally {
            TryDelete(zipPath);
            TryDeleteDirectory(extractDir);
        }
    }

    internal static TimeSpan DownloadTimeout { get; set; } = TimeSpan.FromSeconds(60);

    private static void DownloadArchive(string zipUrl, string zipPath) {
        using var client = new HttpClient {
            Timeout = DownloadTimeout
        };

        client.DefaultRequestHeaders.UserAgent.ParseAdd("AMT.PowerShell.Common/1.0");

        var bytes = client.GetByteArrayAsync(zipUrl).GetAwaiter().GetResult();
        File.WriteAllBytes(zipPath, bytes);
    }

    private static string ResolveModuleRoot(string scope) {
        var psModulePath = Environment.GetEnvironmentVariable("PSModulePath") ?? string.Empty;
        var paths = psModulePath
            .Split(Path.PathSeparator)
            .Where(path => !string.IsNullOrWhiteSpace(path))
            .ToArray();

        if (paths.Length == 0) {
            return Path.Combine(Path.GetTempPath(), "PowerShell", "Modules");
        }

        if (string.Equals(scope, "AllUsers", StringComparison.OrdinalIgnoreCase) && paths.Length > 1) {
            return paths[1];
        }

        return paths[0];
    }

    private static string? ParseModuleVersion(string manifestPath) {
        var lines = File.ReadAllLines(manifestPath);
        foreach (var line in lines) {
            var match = Regex.Match(line, "^\\s*ModuleVersion\\s*=\\s*'(?<version>[^']+)'", RegexOptions.IgnoreCase);
            if (match.Success) {
                return match.Groups["version"].Value;
            }
        }

        return null;
    }

    private static void CopyDirectoryContents(string sourceDirectory, string destinationDirectory) {
        foreach (var directory in Directory.GetDirectories(sourceDirectory, "*", SearchOption.AllDirectories)) {
            var relative = directory.Substring(sourceDirectory.Length).TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            Directory.CreateDirectory(Path.Combine(destinationDirectory, relative));
        }

        foreach (var file in Directory.GetFiles(sourceDirectory, "*", SearchOption.AllDirectories)) {
            var relative = file.Substring(sourceDirectory.Length).TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            var destination = Path.Combine(destinationDirectory, relative);
            var folder = Path.GetDirectoryName(destination);

            if (!string.IsNullOrWhiteSpace(folder)) {
                Directory.CreateDirectory(folder);
            }

            File.Copy(file, destination, overwrite: true);
        }
    }

    private static void TryDelete(string path) {
        try {
            if (File.Exists(path)) {
                File.Delete(path);
            }
        } catch {
        }
    }

    private static void TryDeleteDirectory(string path) {
        try {
            if (Directory.Exists(path)) {
                Directory.Delete(path, recursive: true);
            }
        } catch {
        }
    }
}

internal static class NetworkConnectionOperations {
    internal static Func<bool>? NetworkConnectionProbeOverride { get; set; }

    internal static bool HasAnyInternetCapableNetworkInterface() {
        if (NetworkConnectionProbeOverride is not null) {
            return NetworkConnectionProbeOverride();
        }

        try {
            return NetworkInterface
                .GetAllNetworkInterfaces()
                .Any(networkInterface =>
                    networkInterface.OperationalStatus == OperationalStatus.Up
                    && networkInterface.NetworkInterfaceType != NetworkInterfaceType.Loopback
                    && networkInterface.NetworkInterfaceType != NetworkInterfaceType.Tunnel);
        } catch {
            return false;
        }
    }
}

internal static class UtilsOperations {
    private static readonly Encoding[] KnownBomEncodings = {
        new UTF8Encoding(true),
        new UnicodeEncoding(true, true),
        new UnicodeEncoding(false, true),
        new UTF32Encoding(true, true),
        new UTF32Encoding(false, true)
    };

    internal static string ConvertToInvokableValue(object? value) {
        if (value is null) {
            return "$null";
        }

        if (value is bool boolValue) {
            return boolValue ? "$True" : "$False";
        }

        if (value is string stringValue) {
            return QuoteString(stringValue);
        }

        if (IsNumber(value)) {
            return Convert.ToString(value, CultureInfo.InvariantCulture) ?? "0";
        }

        if (value is IDictionary dictionary) {
            var entries = new List<string>();
            foreach (DictionaryEntry entry in dictionary) {
                entries.Add($"{entry.Key} = {ConvertToInvokableValue(entry.Value)}");
            }

            return entries.Count == 0
                ? "@{}"
                : "@{" + string.Join("; ", entries) + "}";
        }

        if (value is PSObject psObject && IsPowerShellCustomObject(psObject)) {
            var properties = psObject.Properties
                .Where(property => property.IsGettable)
                .Select(property => $"{property.Name}={ConvertToInvokableValue(property.Value)}")
                .ToArray();

            return "[PSCustomObject]@{" + string.Join("; ", properties) + "}";
        }

        if (value is IEnumerable enumerable && value is not string) {
            var values = new List<string>();
            foreach (var element in enumerable) {
                values.Add(ConvertToInvokableValue(element));
            }

            return "@(" + string.Join(", ", values) + ")";
        }

        return QuoteString(value.ToString() ?? string.Empty);
    }

    internal static byte[] RemoveEncodingBom(byte[] bytes, Encoding encoding) {
        var bom = encoding.GetPreamble();
        if (bom.Length == 0 || bytes.Length < bom.Length) {
            return bytes;
        }

        for (var i = 0; i < bom.Length; i++) {
            if (bytes[i] != bom[i]) {
                return bytes;
            }
        }

        var output = new byte[bytes.Length - bom.Length];
        Buffer.BlockCopy(bytes, bom.Length, output, 0, output.Length);
        return output;
    }

    internal static Encoding GetContentEncoding(byte[] contentBytes) {
        foreach (var encoding in KnownBomEncodings) {
            var bom = encoding.GetPreamble();
            if (bom.Length == 0 || contentBytes.Length < bom.Length) {
                continue;
            }

            var matches = true;
            for (var i = 0; i < bom.Length; i++) {
                if (contentBytes[i] == bom[i]) {
                    continue;
                }

                matches = false;
                break;
            }

            if (matches) {
                return encoding;
            }
        }

        return Encoding.UTF8;
    }

    internal static Ast? GetAst(object? inputObject) {
        if (inputObject is null) {
            return null;
        }

        switch (inputObject) {
            case string inputString:
                return File.Exists(inputString)
                    ? Parser.ParseFile(Path.GetFullPath(inputString), out _, out _)
                    : Parser.ParseInput(inputString, out _, out _);
            case FunctionInfo functionInfo:
                return functionInfo.ScriptBlock.Ast;
            case ExternalScriptInfo externalScriptInfo:
                return externalScriptInfo.ScriptBlock.Ast;
            case ScriptBlock scriptBlock:
                return scriptBlock.Ast;
            case Ast ast:
                return ast;
            default:
                return null;
        }
    }

    internal static Type[]? GetReturnTypes(Ast? ast, Func<string, object?> variableResolver) {
        if (ast is null) {
            return null;
        }

        var returnStatements = ast
            .FindAll(static element => element is ReturnStatementAst, searchNestedScriptBlocks: true)
            .OfType<ReturnStatementAst>()
            .ToArray();

        if (returnStatements.Length == 0) {
            return null;
        }

        var returnTypes = new List<Type>();

        foreach (var returnStatement in returnStatements) {
            if (returnStatement.Pipeline is not PipelineAst pipeline
                || pipeline.PipelineElements.Count == 0) {
                return null;
            }

            var expression = GetExpression(pipeline.PipelineElements[0]);
            if (expression is null) {
                return null;
            }

            if (expression is VariableExpressionAst variableExpression) {
                var variableName = variableExpression.VariablePath.UserPath;

                if (string.Equals(variableName, "null", StringComparison.OrdinalIgnoreCase)) {
                    returnTypes.Add(typeof(void));
                    continue;
                }

                if (string.Equals(variableName, "true", StringComparison.OrdinalIgnoreCase)
                    || string.Equals(variableName, "false", StringComparison.OrdinalIgnoreCase)) {
                    returnTypes.Add(typeof(bool));
                    continue;
                }

                var variableValue = variableResolver(variableName);
                if (variableValue is not null) {
                    returnTypes.Add(variableValue.GetType());
                }

                continue;
            }

            returnTypes.Add(expression.StaticType ?? typeof(object));
        }

        return returnTypes
            .Distinct()
            .OrderBy(type => type.FullName, StringComparer.Ordinal)
            .ToArray();
    }

    internal static bool TestParameters(Ast? ast, IReadOnlyCollection<string> validTypes) {
        if (ast is null) {
            return false;
        }

        var parameters = ast
            .FindAll(static element => element is ParameterAst, searchNestedScriptBlocks: true)
            .OfType<ParameterAst>();

        foreach (var parameter in parameters) {
            var typeName = parameter.StaticType.Name;
            if (!validTypes.Contains(typeName, StringComparer.OrdinalIgnoreCase)) {
                return false;
            }
        }

        return true;
    }

    internal static string GetEtag(string path, int chunkSize) {
        if (chunkSize <= 0) {
            throw new ArgumentOutOfRangeException(nameof(chunkSize), "ChunkSize must be greater than zero.");
        }

        using var stream = File.OpenRead(path);
        if (stream.Length == 0) {
            using var emptyMd5 = MD5.Create();
            var emptyHash = emptyMd5.ComputeHash(Array.Empty<byte>());
            return ToHex(emptyHash);
        }

        var partDigests = new List<byte[]>();
        var buffer = new byte[chunkSize];

        using var md5 = MD5.Create();
        while (true) {
            var bytesRead = stream.Read(buffer, 0, chunkSize);
            if (bytesRead <= 0) {
                break;
            }

            var digest = md5.ComputeHash(buffer, 0, bytesRead);
            partDigests.Add(digest);
        }

        if (partDigests.Count == 1) {
            return ToHex(partDigests[0]);
        }

        var combinedBytes = new byte[partDigests.Count * 16];
        for (var index = 0; index < partDigests.Count; index++) {
            Buffer.BlockCopy(partDigests[index], 0, combinedBytes, index * 16, 16);
        }

        var combinedHash = md5.ComputeHash(combinedBytes);
        return $"{ToHex(combinedHash)}-{partDigests.Count}";
    }

    internal static bool CompareFileHashToS3ETag(string path, string etag) {
        var normalizedEtag = etag.Trim().Trim('"');

        var fileSize = new FileInfo(path).Length;
        var parts = ParsePartCount(normalizedEtag);
        var candidatePartSizes = GetPossiblePartSizes(fileSize, parts);

        foreach (var candidatePartSize in candidatePartSizes) {
            var calculated = GetEtag(path, candidatePartSize);
            if (string.Equals(calculated, normalizedEtag, StringComparison.OrdinalIgnoreCase)) {
                return true;
            }
        }

        return false;
    }

    private static int ParsePartCount(string etag) {
        var segments = etag.Split('-');
        if (segments.Length < 2) {
            return 1;
        }

        return int.TryParse(segments[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsed)
            ? Math.Max(1, parsed)
            : 1;
    }

    private static IReadOnlyCollection<int> GetPossiblePartSizes(long fileSize, int parts) {
        if (fileSize <= 0) {
            return new[] { 1 };
        }

        if (parts <= 1) {
            return new[] { ClampToInt(fileSize) };
        }

        var factor = GetFactorOf1Mb(fileSize, parts);

        var candidates = new List<int> {
            8 * 1024 * 1024,
            15 * 1024 * 1024,
            factor
        };

        var filtered = candidates
            .Where(size => size > 0)
            .Where(size => size < fileSize)
            .Where(size => fileSize / size <= parts)
            .Distinct()
            .ToArray();

        return filtered.Length == 0
            ? new[] { ClampToInt(fileSize) }
            : filtered;
    }

    private static int ClampToInt(long value) {
        if (value > int.MaxValue) {
            return int.MaxValue;
        }

        if (value <= 0) {
            return 1;
        }

        return (int)value;
    }

    private static int GetFactorOf1Mb(long size, int parts) {
        const long oneMb = 1024 * 1024;

        if (size < oneMb && parts <= 1) {
            return ClampToInt(size);
        }

        var chunkSize = size / parts;
        var remainder = chunkSize % oneMb;

        var adjusted = chunkSize + oneMb - remainder;
        return ClampToInt(adjusted);
    }

    private static ExpressionAst? GetExpression(Ast pipelineElement) =>
        pipelineElement switch {
            CommandExpressionAst commandExpression => commandExpression.Expression,
            ExpressionAst expression => expression,
            _ => null
        };

    private static bool IsPowerShellCustomObject(PSObject psObject) {
        if (psObject.BaseObject is PSCustomObject) {
            return true;
        }

        return psObject.TypeNames.Any(typeName =>
            string.Equals(typeName, "System.Management.Automation.PSCustomObject", StringComparison.Ordinal));
    }

    private static bool IsNumber(object value) => value switch {
        byte => true,
        sbyte => true,
        short => true,
        ushort => true,
        int => true,
        uint => true,
        long => true,
        ulong => true,
        float => true,
        double => true,
        decimal => true,
        _ => false
    };

    private static string QuoteString(string value) {
        var escaped = value
            .Replace("`", "``")
            .Replace("\"", "`\"")
            .Replace("$", "`$")
            .Replace("\r", "`r")
            .Replace("\n", "`n")
            .Replace("\t", "`t");

        return $"\"{escaped}\"";
    }

    private static string ToHex(byte[] bytes) {
        var builder = new StringBuilder(bytes.Length * 2);
        foreach (var value in bytes) {
            builder.Append(value.ToString("X2", CultureInfo.InvariantCulture));
        }

        return builder.ToString();
    }
}

/// <summary>Converts a value to a PowerShell-invokable string representation.</summary>
/// <remarks>
/// Null, strings, numbers, booleans, and PSObjects are each serialised to a canonical
/// form that can be embedded in a script and re-evaluated.
/// </remarks>
/// <example>
/// <code>ConvertTo-InvokableValue -Value 42</code>
/// Returns the string "42".
/// </example>
/// <example>
/// <code>ConvertTo-InvokableValue -Value $null</code>
/// Returns the string "$null".
/// </example>
[Cmdlet("ConvertTo", "InvokableValue")]
[OutputType(typeof(string))]
public sealed class ConvertToInvokableValueCommand : PSCmdlet {
    /// <summary>The value to convert; accepts null and any PowerShell-compatible type.</summary>
    [Parameter(Mandatory = true)]
    [AllowNull]
    public object? Value { get; set; }

    protected override void ProcessRecord() =>
        WriteObject(UtilsOperations.ConvertToInvokableValue(Value));
}

/// <summary>Strips the byte-order mark (BOM) from a byte array for the given encoding.</summary>
/// <remarks>
/// Returns the input byte array unchanged when no BOM is present.
/// </remarks>
/// <example>
/// <code>Remove-EncodingBom -Bytes $bytes -Encoding ([System.Text.Encoding]::UTF8)</code>
/// Returns $bytes with the UTF-8 BOM removed if present.
/// </example>
[Cmdlet("Remove", "EncodingBom")]
[OutputType(typeof(byte[]))]
public sealed class RemoveEncodingBomCommand : PSCmdlet {
    /// <summary>The byte array to strip the BOM from.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNull]
    public byte[] Bytes { get; set; } = Array.Empty<byte>();

    /// <summary>The encoding whose BOM prefix to remove.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNull]
    public Encoding Encoding { get; set; } = Encoding.UTF8;

    protected override void ProcessRecord() =>
        WriteObject(UtilsOperations.RemoveEncodingBom(Bytes, Encoding));
}

/// <summary>Detects the text encoding of a file or byte array by inspecting its BOM.</summary>
/// <remarks>
/// Reads up to the first four bytes of the input to identify a byte-order mark.
/// Falls back to UTF-8 when no recognised BOM is present.
/// </remarks>
/// <example>
/// <code>Get-ContentEncoding -Path 'C:\file.txt'</code>
/// Returns the Encoding detected from the file's BOM.
/// </example>
/// <example>
/// <code>Get-ContentEncoding -ContentBytes $bytes</code>
/// Returns the Encoding detected from the leading bytes.
/// </example>
[Cmdlet("Get", "ContentEncoding", DefaultParameterSetName = "Bytes")]
[OutputType(typeof(Encoding))]
public sealed class GetContentEncodingCommand : PSCmdlet {
    /// <summary>Raw bytes to inspect for a BOM (Bytes parameter set).</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Bytes")]
    [ValidateNotNull]
    public byte[] ContentBytes { get; set; } = Array.Empty<byte>();

    /// <summary>Path to the file whose leading bytes are inspected for a BOM (Path parameter set).</summary>
    [Parameter(Mandatory = true, ParameterSetName = "Path")]
    [ValidateNotNullOrEmpty]
    public string Path { get; set; } = string.Empty;

    protected override void ProcessRecord() {
        byte[] bytes;

        if (ParameterSetName == "Path") {
            if (!File.Exists(Path)) {
                throw new FileNotFoundException($"The file '{Path}' does not exist.", Path);
            }

            using var stream = File.OpenRead(Path);
            var readLength = (int)Math.Min(stream.Length, 4);
            bytes = new byte[readLength];

            if (readLength > 0) {
                stream.Read(bytes, 0, readLength);
            }
        } else {
            bytes = ContentBytes;
        }

        WriteObject(UtilsOperations.GetContentEncoding(bytes));
    }
}

/// <summary>Returns the cached value of a process environment variable, computing and saving it on first access.</summary>
/// <remarks>
/// If the variable already exists and passes optional validation, its value is returned immediately.
/// Otherwise the LazyValue script block is invoked, the result is stored in the environment variable,
/// and the value is returned.
/// </remarks>
/// <example>
/// <code>Get-VarOrSave -VariableName 'MY_VAR' -LazyValue { 'computed' }</code>
/// Returns the value of MY_VAR, computing it via the script block on first call.
/// </example>
/// <example>
/// <code>Get-VarOrSave -VariableName 'MY_VAR' -LazyValue { Get-Thing } -Validate { $_ -ne $null }</code>
/// Recomputes MY_VAR if the existing value fails validation.
/// </example>
[Cmdlet("Get", "VarOrSave")]
[OutputType(typeof(object))]
public sealed class GetVarOrSaveCommand : PSCmdlet {
    /// <summary>The process environment variable name used to cache the value.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    public string VariableName { get; set; } = string.Empty;

    /// <summary>Script block invoked to compute the value when the variable is absent or invalid.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNull]
    public ScriptBlock LazyValue { get; set; } = null!;

    /// <summary>Optional script block that validates the cached value; a falsy result triggers recomputation.</summary>
    [Parameter]
    public ScriptBlock? Validate { get; set; }

    protected override void ProcessRecord() {
        var envValue = Environment.GetEnvironmentVariable(VariableName, EnvironmentVariableTarget.Process);

        if (!string.IsNullOrEmpty(envValue)) {
            if (Validate is null) {
                WriteObject(envValue);
                return;
            }

            try {
                if (IsValid(Validate, envValue)) {
                    WriteObject(envValue);
                    return;
                }

                Environment.SetEnvironmentVariable(VariableName, null, EnvironmentVariableTarget.Process);
            } catch {
                Environment.SetEnvironmentVariable(VariableName, null, EnvironmentVariableTarget.Process);
            }
        }

        while (true) {
            object? value;
            try {
                value = LazyValue.InvokeReturnAsIs();
            } catch {
                WriteObject(null);
                return;
            }

            if (Validate is null || IsValid(Validate, value)) {
                var valueString = value?.ToString();
                Environment.SetEnvironmentVariable(VariableName, valueString, EnvironmentVariableTarget.Process);
                WriteObject(value);
                return;
            }
        }
    }

    private static bool IsValid(ScriptBlock validator, object? value) {
        var result = validator.InvokeReturnAsIs(value);

        if (result is PSObject psObject) {
            result = psObject.BaseObject;
        }

        return LanguagePrimitives.IsTrue(result);
    }
}

/// <summary>Returns the PowerShell AST for a script block, script file path, or existing Ast node.</summary>
/// <remarks>
/// Accepts a ScriptBlock, a file path string, or an existing Ast node.
/// Returns nothing when the input cannot be parsed as a script.
/// </remarks>
/// <example>
/// <code>Get-Ast -InputObject { param($x) $x }</code>
/// Returns the ScriptBlockAst for the given script block.
/// </example>
[Cmdlet("Get", "Ast")]
[OutputType(typeof(Ast))]
public sealed class GetAstCommand : PSCmdlet {
    /// <summary>The script block, file path, or Ast node to parse into an Ast tree.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNull]
    public object InputObject { get; set; } = null!;

    protected override void ProcessRecord() {
        var ast = UtilsOperations.GetAst(InputObject);
        if (ast is not null) {
            WriteObject(ast);
        }
    }
}

/// <summary>Infers the .NET return types of a PowerShell script block or AST.</summary>
/// <remarks>
/// Performs static analysis of the AST output pipeline to determine possible return types.
/// Variable references in the script are resolved against the current session state.
/// </remarks>
/// <example>
/// <code>Get-ReturnType -InputObject { [string]'hello' }</code>
/// Returns typeof(string).
/// </example>
[Cmdlet("Get", "ReturnType")]
[OutputType(typeof(Type[]))]
public sealed class GetReturnTypeCommand : PSCmdlet {
    /// <summary>The script block, file path, or Ast node to analyse for return types.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNull]
    public object InputObject { get; set; } = null!;

    protected override void ProcessRecord() {
        var ast = UtilsOperations.GetAst(InputObject);
        var returnTypes = UtilsOperations.GetReturnTypes(ast, ResolveVariable);

        if (returnTypes is not null) {
            foreach (var returnType in returnTypes) {
                WriteObject(returnType);
            }
        }
    }

    private object? ResolveVariable(string variableName) {
        try {
            return GetVariableValue(variableName);
        } catch {
            return null;
        }
    }
}

/// <summary>Tests whether a script block's inferred return types are all within the allowed set.</summary>
/// <remarks>
/// Returns <see langword="true"/> when every inferred return type is contained in ValidTypes,
/// otherwise <see langword="false"/>.
/// When AllowNull is specified, void/null returns do not cause a failure.
/// </remarks>
/// <example>
/// <code>Test-ReturnType -InputObject { 'hello' } -ValidTypes ([string])</code>
/// Returns $true because the script block returns string.
/// </example>
/// <example>
/// <code>Test-ReturnType -InputObject { $null } -ValidTypes ([string]) -AllowNull</code>
/// Returns $true because null is allowed.
/// </example>
[Cmdlet("Test", "ReturnType")]
[OutputType(typeof(bool))]
public sealed class TestReturnTypeCommand : PSCmdlet {
    /// <summary>The script block, file path, or Ast node whose return types are tested.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNull]
    public object InputObject { get; set; } = null!;

    /// <summary>The set of .NET types that the script block is allowed to return.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    public Type[] ValidTypes { get; set; } = Array.Empty<Type>();

    /// <summary>When set, allows void/null return types even if they are not in ValidTypes.</summary>
    [Parameter]
    public SwitchParameter AllowNull { get; set; }

    protected override void ProcessRecord() {
        var ast = UtilsOperations.GetAst(InputObject);
        var returnTypes = UtilsOperations.GetReturnTypes(ast, ResolveVariable);

        if (returnTypes is null) {
            WriteObject(false);
            return;
        }

        foreach (var returnType in returnTypes) {
            if (ValidTypes.Contains(returnType)) {
                continue;
            }

            if (AllowNull.IsPresent && returnType == typeof(void)) {
                continue;
            }

            WriteObject(false);
            return;
        }

        WriteObject(true);
    }

    private object? ResolveVariable(string variableName) {
        try {
            return GetVariableValue(variableName);
        } catch {
            return null;
        }
    }
}

/// <summary>Tests whether all parameters in a script block are declared with types from the allowed set.</summary>
/// <remarks>
/// Statically analyses the param block of the input script to verify that every parameter
/// type name is present in ValidTypes.
/// </remarks>
/// <example>
/// <code>Test-Parameters -InputObject { param([string]$x) } -ValidTypes 'string'</code>
/// Returns $true because the parameter is typed as string.
/// </example>
[Cmdlet("Test", "Parameters")]
[OutputType(typeof(bool))]
public sealed class TestParametersCommand : PSCmdlet {
    /// <summary>The script block, file path, or Ast node whose parameters are validated.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNull]
    public object InputObject { get; set; } = null!;

    /// <summary>The set of type name strings that parameters are permitted to use.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    public string[] ValidTypes { get; set; } = Array.Empty<string>();

    protected override void ProcessRecord() {
        var ast = UtilsOperations.GetAst(InputObject);
        WriteObject(UtilsOperations.TestParameters(ast, ValidTypes));
    }
}

/// <summary>Downloads and installs a PowerShell module from a GitHub repository archive.</summary>
/// <remarks>
/// Fetches the branch's zip archive from GitHub, extracts the module, copies it into the
/// appropriate PowerShell modules directory, and returns the installed module name.
/// Requires internet access.
/// </remarks>
/// <example>
/// <code>Install-ModuleFromGitHub -GitHubRepo 'org/repo' -Branch 'main'</code>
/// Installs the module for the current user from the main branch.
/// </example>
/// <example>
/// <code>Install-ModuleFromGitHub -GitHubRepo 'org/repo' -Branch 'main' -Scope AllUsers</code>
/// Installs the module for all users (requires elevation).
/// </example>
[Cmdlet("Install", "ModuleFromGitHub")]
[OutputType(typeof(string))]
public sealed class InstallModuleFromGitHubCommand : PSCmdlet {
    /// <summary>The GitHub repository in "owner/repo" format from which to download the module.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    public string GitHubRepo { get; set; } = string.Empty;

    /// <summary>The branch name to download the archive from.</summary>
    [Parameter(Mandatory = true)]
    [ValidateNotNullOrEmpty]
    public string Branch { get; set; } = string.Empty;

    /// <summary>The installation scope; "CurrentUser" (default) or "AllUsers" (requires elevation).</summary>
    [Parameter]
    [ValidateSet("CurrentUser", "AllUsers")]
    public string Scope { get; set; } = "CurrentUser";

    protected override void ProcessRecord() {
        var request = new InstallModuleRequest {
            GitHubRepo = GitHubRepo,
            Branch = Branch,
            Scope = Scope
        };

        var moduleName = InstallModuleFromGitHubOperations.Install(request, this);
        WriteObject(moduleName);
    }
}

/// <summary>Tests whether any network interface with internet connectivity is available.</summary>
/// <remarks>
/// Inspects local network interfaces for an operational adapter that is internet-capable.
/// Returns <see langword="true"/> when such an interface exists, otherwise <see langword="false"/>.
/// </remarks>
/// <example>
/// <code>Test-NetworkConnection</code>
/// Returns $true if at least one internet-capable network interface is up.
/// </example>
[Cmdlet("Test", "NetworkConnection")]
[OutputType(typeof(bool))]
public sealed class TestNetworkConnectionCommand : PSCmdlet {
    protected override void ProcessRecord() =>
        WriteObject(NetworkConnectionOperations.HasAnyInternetCapableNetworkInterface());
}

/// <summary>Starts a PowerShell script block asynchronously and returns an AsyncTaskRun token.</summary>
/// <remarks>
/// Launches the script in a new PowerShell runspace using BeginInvoke.
/// The returned AsyncTaskRun can be passed to Wait-Task to collect the result.
/// Also available as the alias <c>async</c>.
/// </remarks>
/// <example>
/// <code>$run = Start-AsyncTask { Start-Sleep 5; 'done' }</code>
/// Starts the script asynchronously and stores the run token.
/// </example>
/// <example>
/// <code>$run = async { Get-ChildItem C:\ -Recurse }</code>
/// Same as above using the async alias.
/// </example>
[Cmdlet("Start", "AsyncTask")]
[Alias("async")]
[OutputType(typeof(AsyncTaskRun))]
public sealed class StartAsyncTaskCommand : PSCmdlet {
    /// <summary>The script block to execute asynchronously in a new PowerShell runspace.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNull]
    public ScriptBlock ScriptBlock { get; set; } = null!;

    /// <summary>Optional pipeline input attached to the AsyncTaskRun token for correlation.</summary>
    [Parameter(ValueFromPipeline = true)]
    public object? InputObject { get; set; }

    protected override void ProcessRecord() {
        var powerShell = System.Management.Automation.PowerShell.Create();
        powerShell.AddScript(ScriptBlock.ToString());

        var job = powerShell.BeginInvoke();
        WriteObject(new AsyncTaskRun(InputObject, powerShell, job));
    }
}

/// <summary>Waits for one or more AsyncTaskRun or Task objects to complete and emits their results.</summary>
/// <remarks>
/// Collects all piped run objects in ProcessRecord, then blocks in EndProcessing until each completes.
/// By default emits the result value; with PassThru emits the original run or Task object.
/// Also available as the alias <c>await</c>.
/// </remarks>
/// <example>
/// <code>async { 'hello' } | await</code>
/// Starts an async task and waits for the result, returning "hello".
/// </example>
/// <example>
/// <code>Start-AsyncTask { 'data' } | Wait-Task -PassThru</code>
/// Waits for the task and emits the original AsyncTaskRun object.
/// </example>
[Cmdlet("Wait", "Task")]
[Alias("await")]
[OutputType(typeof(object))]
public sealed class WaitTaskCommand : PSCmdlet {
    private readonly List<object> _running = new();

    /// <summary>An AsyncTaskRun or Task object, or a collection of them, to wait for; accepted from the pipeline.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [ValidateNotNull]
    public object Run { get; set; } = null!;

    /// <summary>When set, emits the original AsyncTaskRun or Task object instead of its result.</summary>
    [Parameter]
    public SwitchParameter PassThru { get; set; }

    protected override void ProcessRecord() {
        AddRunObject(Run);
    }

    protected override void EndProcessing() {
        foreach (var item in _running) {
            switch (item) {
                case AsyncTaskRun asyncTaskRun:
                    CompleteAsyncTaskRun(asyncTaskRun);
                    break;
                case Task task:
                    CompleteTask(task);
                    break;
                default:
                    throw new InvalidOperationException("The Run object must be AsyncTaskRun, Task, or a collection of those types.");
            }
        }
    }

    private void AddRunObject(object? value) {
        if (value is null) {
            return;
        }

        if (value is PSObject psObject) {
            AddRunObject(psObject.BaseObject);
            return;
        }

        if (value is IEnumerable enumerable && value is not string && value is not AsyncTaskRun && value is not Task) {
            foreach (var item in enumerable) {
                AddRunObject(item);
            }

            return;
        }

        _running.Add(value);
    }

    private void CompleteAsyncTaskRun(AsyncTaskRun run) {
        if (run.Result is null) {
            try {
                run.Job.AsyncWaitHandle.WaitOne();
                var output = run.PowerShell.EndInvoke(run.Job);
                run.Result = ConvertOutput(output);
            } catch (Exception exception) {
                run.Result = exception.InnerException ?? exception;
            } finally {
                run.PowerShell.Dispose();
            }
        }

        if (PassThru.IsPresent) {
            WriteObject(run);
        } else {
            WriteObject(run.Result);
        }
    }

    private void CompleteTask(Task task) {
        object? result;

        try {
            task.GetAwaiter().GetResult();

            var resultProperty = task.GetType().GetProperty("Result");
            result = resultProperty?.GetValue(task);
        } catch (Exception exception) {
            result = exception.InnerException ?? exception;
        }

        if (PassThru.IsPresent) {
            WriteObject(task);
        } else {
            WriteObject(result);
        }
    }

    private static object? ConvertOutput(IEnumerable<PSObject> output) {
        var items = output.ToList();

        if (items.Count == 0) {
            return null;
        }

        if (items.Count == 1) {
            return items[0].BaseObject;
        }

        return items.Select(item => item.BaseObject).ToArray();
    }
}

/// <summary>Adds a lazily-evaluated script property to a PSObject.</summary>
/// <remarks>
/// The script block is only executed the first time the property is accessed.
/// Subsequent reads return the memoised value stored as a NoteProperty.
/// </remarks>
/// <example>
/// <code>$obj | Add-LazyProperty -Name 'Hash' -Value { Get-FileHash $this.Path }</code>
/// Attaches a lazy Hash property that computes on first access.
/// </example>
/// <example>
/// <code>$obj | Add-LazyProperty -Name 'Hash' -Value { Get-FileHash $this.Path } -PassThru</code>
/// Same as above, returning the modified PSObject.
/// </example>
[Cmdlet("Add", "LazyProperty")]
[OutputType(typeof(PSObject))]
public sealed class AddLazyPropertyCommand : PSCmdlet {
    /// <summary>The PSObject to attach the lazy property to; accepted from the pipeline.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true)]
    [ValidateNotNull]
    public PSObject InputObject { get; set; } = null!;

    /// <summary>The name of the property to add.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    public string Name { get; set; } = string.Empty;

    /// <summary>Script block invoked on first property access to compute the property value.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [ValidateNotNull]
    public ScriptBlock Value { get; set; } = null!;

    /// <summary>When set, emits the modified InputObject to the pipeline.</summary>
    [Parameter]
    public SwitchParameter PassThru { get; set; }

    protected override void ProcessRecord() {
        var lazyScriptBlockProperty = $"__amt_lazyproperty_{Guid.NewGuid():N}";

        InputObject.Properties.Remove(Name);
        InputObject.Properties.Remove(lazyScriptBlockProperty);
        InputObject.Properties.Add(new PSNoteProperty(lazyScriptBlockProperty, Value.GetNewClosure()));

        var escapedScriptBlockProperty = EscapeSingleQuoted(lazyScriptBlockProperty);
        var escapedPropertyName = EscapeSingleQuoted(Name);

        var lazyPropertyGetter = ScriptBlock.Create($"$result = & $this.PSObject.Properties['{escapedScriptBlockProperty}'].Value\n"
            + $"Add-Member -InputObject $this -MemberType NoteProperty -Name '{escapedPropertyName}' -Value $result -Force\n"
            + "$result");

        InputObject.Properties.Add(new PSScriptProperty(Name, lazyPropertyGetter));

        if (PassThru.IsPresent) {
            WriteObject(InputObject);
        }
    }

    private static string EscapeSingleQuoted(string value) =>
        value.Replace("'", "''");
}

/// <summary>Defines a read-only script variable whose value is computed lazily on first access.</summary>
/// <remarks>
/// The variable is set in the caller's local scope as read-only.
/// The first time it is read, the Value script block executes and the result is memoised.
/// Also available as the alias <c>lazy</c>.
/// </remarks>
/// <example>
/// <code>Set-LazyVariable -Name 'Config' -Value { Import-PowerShellDataFile 'config.psd1' }</code>
/// Creates a lazy $Config variable that loads the config file on first use.
/// </example>
/// <example>
/// <code>lazy Config { Import-PowerShellDataFile 'config.psd1' }</code>
/// Same as above using the lazy alias.
/// </example>
[Cmdlet("Set", "LazyVariable")]
[Alias("lazy")]
[OutputType(typeof(ScriptBlock))]
public sealed class SetLazyVariableCommand : PSCmdlet {
    /// <summary>The variable name to create in the caller's local scope.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    public string Name { get; set; } = string.Empty;

    /// <summary>Script block invoked on first access to compute the variable's value.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [ValidateNotNull]
    public ScriptBlock Value { get; set; } = null!;

    /// <summary>When set, emits the generated lazy script block to the pipeline.</summary>
    [Parameter]
    public SwitchParameter PassThru { get; set; }

    protected override void ProcessRecord() {
        var source = Value.GetNewClosure();

        var factory = ScriptBlock.Create(
            "param($Source, $VariableName)\n"
            + "{\n"
            + "    $sourceBlock = if ($Source -is [System.Management.Automation.PSObject]) { $Source.BaseObject } else { $Source }\n"
            + "    $result = & $sourceBlock\n"
            + "    Set-Variable -Name $VariableName -Value $result -Scope Local -Option ReadOnly\n"
            + "    $result\n"
            + "}.GetNewClosure()\n");

        var lazyValueObject = factory.InvokeReturnAsIs(source, Name);
        var lazyValue = lazyValueObject as ScriptBlock
            ?? (lazyValueObject as PSObject)?.BaseObject as ScriptBlock
            ?? throw new InvalidOperationException("Failed to create lazy script block.");

        SessionState.PSVariable.Set(new PSVariable(Name, lazyValue, ScopedItemOptions.ReadOnly));

        if (PassThru.IsPresent) {
            WriteObject(lazyValue);
        }
    }
}

/// <summary>Tests whether the current process is running as the NT AUTHORITY\SYSTEM account.</summary>
/// <remarks>
/// Returns <see langword="false"/> on non-Windows platforms without throwing.
/// </remarks>
/// <example>
/// <code>Test-IsRunningAsSystem</code>
/// Returns $true when the PowerShell host is running as SYSTEM.
/// </example>
[Cmdlet("Test", "IsRunningAsSystem")]
[OutputType(typeof(bool))]
public sealed class TestIsRunningAsSystemCommand : PSCmdlet {
    protected override void ProcessRecord() {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) {
            WriteObject(false);
            return;
        }

        var userName = Environment.UserName;
        var userDomain = Environment.UserDomainName;

        var isSystem = string.Equals(userDomain, "NT AUTHORITY", StringComparison.OrdinalIgnoreCase)
            && string.Equals(userName, "SYSTEM", StringComparison.OrdinalIgnoreCase);

        WriteObject(isSystem);
    }
}

/// <summary>Tests whether the current operating system is Windows 11 or later.</summary>
/// <remarks>
/// Returns <see langword="false"/> on non-Windows platforms without throwing.
/// Detects Windows 11 by OS description string or build number >= 22000.
/// </remarks>
/// <example>
/// <code>Test-IsWindows11</code>
/// Returns $true when running on Windows 11 or later.
/// </example>
[Cmdlet("Test", "IsWindows11")]
[OutputType(typeof(bool))]
public sealed class TestIsWindows11Command : PSCmdlet {
    protected override void ProcessRecord() {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows)) {
            WriteObject(false);
            return;
        }

        var description = RuntimeInformation.OSDescription;
        var isWindows11 = description.IndexOf("Windows 11", StringComparison.OrdinalIgnoreCase) >= 0
            || Environment.OSVersion.Version.Build >= 22000;

        WriteObject(isWindows11);
    }
}

/// <summary>Compares a local file's computed hash to an S3 ETag to verify integrity.</summary>
/// <remarks>
/// Supports both single-part (MD5) and multi-part ETags.
/// Returns <see langword="true"/> when the computed hash matches the ETag.
/// </remarks>
/// <example>
/// <code>Compare-FileHashToS3ETag -Path 'C:\file.bin' -ETag '"abc123"'</code>
/// Returns $true if the file's computed hash matches the ETag.
/// </example>
[Cmdlet("Compare", "FileHashToS3ETag")]
[OutputType(typeof(bool))]
public sealed class CompareFileHashToS3EtagCommand : PSCmdlet {
    /// <summary>Path to the local file to hash.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string Path { get; set; } = string.Empty;

    /// <summary>The S3 ETag string to compare against, with or without surrounding quotes.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateNotNullOrEmpty]
    public string ETag { get; set; } = string.Empty;

    protected override void ProcessRecord() =>
        WriteObject(UtilsOperations.CompareFileHashToS3ETag(Path, ETag));
}

/// <summary>Computes an S3-compatible ETag for a local file using the specified chunk size.</summary>
/// <remarks>
/// Splits the file into chunks of ChunkSize bytes, hashes each chunk with MD5, then hashes the
/// concatenated digests to produce a multi-part ETag of the form "hash-N".
/// </remarks>
/// <example>
/// <code>Get-ETag -Path 'C:\file.bin' -ChunkSize 8388608</code>
/// Returns the S3 ETag for the file using 8 MiB parts.
/// </example>
[Cmdlet("Get", "ETag")]
[OutputType(typeof(string))]
public sealed class GetEtagCommand : PSCmdlet {
    /// <summary>Path to the file to compute the ETag for.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [ValidateNotNullOrEmpty]
    public string Path { get; set; } = string.Empty;

    /// <summary>The chunk size in bytes used for multi-part ETag calculation; must be at least 1.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateRange(1, int.MaxValue)]
    public int ChunkSize { get; set; }

    protected override void ProcessRecord() =>
        WriteObject(UtilsOperations.GetEtag(Path, ChunkSize));
}



