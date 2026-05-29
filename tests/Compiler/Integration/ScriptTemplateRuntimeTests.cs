// Copyright (c) 2026 James Draycott <me@racci.dev>. All Rights Reserved.
// Licensed under the AGPL-3.0-or-later License, See LICENSE in the project root
// for license information.

using System.Diagnostics;
using System.Globalization;
using System.Text;
using Compiler.Module.Compiled;
using Compiler.Module.Resolvable;
using Compiler.Requirements;

namespace Compiler.Test.Integration;

[TestFixture]
[NonParallelizable]
public sealed class ScriptTemplateRuntimeTests {
    private sealed record ProcessResult(int ExitCode, string StandardOutput, string StandardError);

    [Test]
    public async Task GeneratedScript_ConcurrentRuns_WriteUtf8ModuleOnceAndLeaveReadyMarker() => await InvokeWithInjectedModuleOptOut(async () => {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var outputRoot = TestUtils.GenerateUniqueDirectory();
        var programDataRoot = TestUtils.GenerateUniqueDirectory();
        var tempRoot = TestUtils.GenerateUniqueDirectory();

        var childPath = Path.Combine(sourceRoot, "Child.psm1");
        var scriptPath = Path.Combine(sourceRoot, "Root.ps1");
        var childContent = new StringBuilder();
        childContent.AppendLine("function Invoke-Child {");
        childContent.AppendLine("    [CmdletBinding()]");
        childContent.AppendLine("    param()");
        childContent.AppendLine("    'Child-Ready'");
        childContent.AppendLine("}");
        for (var i = 0; i < 4000; i++) {
            childContent.AppendLine(CultureInfo.InvariantCulture, $"# Padding {i} Ω");
        }

        await File.WriteAllTextAsync(childPath, childContent.ToString());
        await File.WriteAllTextAsync(scriptPath, "using module ./Child.psm1\nInvoke-Child");

        var compiledScriptPath = await CompileScriptToOutput(sourceRoot, outputRoot, scriptPath);
        var results = await RunPwshConcurrently(compiledScriptPath, 6, programDataRoot, tempRoot);
        var modulesRoot = GetModulesRoot(programDataRoot, results);

        var childModuleDirectory = FindSingleModuleDirectory(modulesRoot, "Child-");
        var childModuleFile = Directory.GetFiles(childModuleDirectory, "Child-*.psm1", SearchOption.TopDirectoryOnly).Single();
        var readyPath = Path.Combine(childModuleDirectory, ".ready");

        Assert.Multiple(() => {
            Assert.That(results, Has.Length.EqualTo(6));
            Assert.That(results.All(result => result.ExitCode == 0), Is.True, FormatResults(results));
            Assert.That(results.All(result => result.StandardOutput.Contains("Child-Ready", StringComparison.Ordinal)), Is.True, FormatResults(results));
            Assert.That(File.Exists(childModuleFile), Is.True);
            Assert.That(new FileInfo(childModuleFile).Length, Is.GreaterThan(0));
            Assert.That(File.Exists(readyPath), Is.True);
            Assert.That(Directory.GetFiles(modulesRoot, "*.lock", SearchOption.TopDirectoryOnly), Is.Empty);
        });
    });

    [Test]
    public async Task GeneratedScript_ConcurrentRuns_ExpandZipModuleOnceAndLeaveReadyMarker() => await InvokeWithInjectedModuleOptOut(async () => {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var outputRoot = TestUtils.GenerateUniqueDirectory();
        var programDataRoot = TestUtils.GenerateUniqueDirectory();
        var tempRoot = TestUtils.GenerateUniqueDirectory();
        var commonDir = Path.Combine(sourceRoot, "common");
        Directory.CreateDirectory(commonDir);

        var loggingPath = Path.Combine(commonDir, "Logging.psm1");
        var scriptPath = Path.Combine(sourceRoot, "Root.ps1");

        await File.WriteAllTextAsync(loggingPath, "using module @{ ModuleName = 'PSReadLine'; RequiredVersion = '2.3.5' }\nfunction Invoke-Info { param([string]$Message) $Message }");
        await File.WriteAllTextAsync(scriptPath, "using module ./common/Logging.psm1\nInvoke-Info 'Zip-Ready'");

        await EnsureRemotePackageCached("PSReadLine", "2.3.5", "PSReadLine.2.3.5.nupkg");

        var compiledScriptPath = await CompileScriptToOutput(sourceRoot, outputRoot, scriptPath);
        var results = await RunPwshConcurrently(compiledScriptPath, 4, programDataRoot, tempRoot);
        var modulesRoot = GetModulesRoot(programDataRoot, results);

        var moduleDirectory = FindSingleModuleDirectory(modulesRoot, "PSReadLine-");
        var readyPath = Path.Combine(moduleDirectory, ".ready");
        var extractedFiles = Directory.GetFiles(moduleDirectory, "*", SearchOption.AllDirectories)
            .Where(path => !path.EndsWith(".ready", StringComparison.Ordinal))
            .ToArray();

        Assert.Multiple(() => {
            Assert.That(results, Has.Length.EqualTo(4));
            Assert.That(results.All(result => result.ExitCode == 0), Is.True, FormatResults(results));
            Assert.That(results.All(result => result.StandardOutput.Contains("Zip-Ready", StringComparison.Ordinal)), Is.True, FormatResults(results));
            Assert.That(results.All(result => result.StandardError.Contains("PSReadLine-B8EE4D", StringComparison.Ordinal) is false), Is.True, FormatResults(results));
            Assert.That(results.All(result => result.StandardError.Contains("PackageManagement-", StringComparison.Ordinal) is false), Is.True, FormatResults(results));
            Assert.That(File.Exists(readyPath), Is.True);
            Assert.That(extractedFiles, Is.Not.Empty);
            Assert.That(extractedFiles.Any(path => Path.GetFileName(path).StartsWith("PSReadLine-", StringComparison.OrdinalIgnoreCase) && path.EndsWith(".psd1", StringComparison.OrdinalIgnoreCase)), Is.True);
            Assert.That(Directory.GetFiles(modulesRoot, "*.lock", SearchOption.TopDirectoryOnly), Is.Empty);
        });
    });

    [Test]
    public async Task GeneratedScript_ConcurrentRuns_WithChainedLocalAndRemoteModules_ValidatesExportAndLockBehavior() => await InvokeWithInjectedModuleOptOut(async () => {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var outputRoot = TestUtils.GenerateUniqueDirectory();
        var programDataRoot = TestUtils.GenerateUniqueDirectory();
        var tempRoot = TestUtils.GenerateUniqueDirectory();

        // Layer 1: ModuleA exports a function
        var moduleADir = Path.Combine(sourceRoot, "ModuleA");
        Directory.CreateDirectory(moduleADir);
        var moduleAPath = Path.Combine(moduleADir, "ModuleA.psm1");
        await File.WriteAllTextAsync(moduleAPath, @"
function Get-AValue {
    param()
    'A-Value'
}
Export-ModuleMember -Function Get-AValue
".TrimStart());

        // Layer 2: ModuleB consumes ModuleA via using module, re-exports
        var moduleBDir = Path.Combine(sourceRoot, "ModuleB");
        Directory.CreateDirectory(moduleBDir);
        var moduleBPath = Path.Combine(moduleBDir, "ModuleB.psm1");
        await File.WriteAllTextAsync(moduleBPath, @"
using module ../ModuleA/ModuleA.psm1

function Get-BValue {
    param()
    $a = Get-AValue
    ""B-$a""
}
Export-ModuleMember -Function Get-BValue
".TrimStart());

        // Layer 3: Utility façade consumes ModuleB, exports utility function
        var facadeDir = Path.Combine(sourceRoot, "facade");
        Directory.CreateDirectory(facadeDir);
        var utilityPath = Path.Combine(facadeDir, "Utility.psm1");
        await File.WriteAllTextAsync(utilityPath, @"
using module ../ModuleB/ModuleB.psm1

function Invoke-Utility {
    param()
    $b = Get-BValue
    ""Utility-Result:$b""
}
Export-ModuleMember -Function Invoke-Utility
".TrimStart());

        // Layer 4: Logging module consumes two remote modules
        var commonDir = Path.Combine(sourceRoot, "common");
        Directory.CreateDirectory(commonDir);
        var loggingPath = Path.Combine(commonDir, "Logging.psm1");
        await File.WriteAllTextAsync(loggingPath, @"
using module @{ ModuleName = 'PSReadLine'; RequiredVersion = '2.3.5' }
using module @{ ModuleName = 'PackageManagement'; RequiredVersion = '1.4.8.1' }

function Invoke-LogInfo {
    param([string]$Message)
    'Logged: ' + $Message
}
Export-ModuleMember -Function Invoke-LogInfo
".TrimStart());

        // Root script: import both facade modules, emit deterministic output
        var scriptPath = Path.Combine(sourceRoot, "Root.ps1");
        await File.WriteAllTextAsync(scriptPath, @"
using module ./facade/Utility.psm1
using module ./common/Logging.psm1

$(Invoke-Utility)
$(Invoke-LogInfo 'All-Exports-Work')
".TrimStart());

        await EnsureRemotePackageCached("PSReadLine", "2.3.5", "PSReadLine.2.3.5.nupkg");
        await EnsureRemotePackageCached("PackageManagement", "1.4.8.1", "PackageManagement.1.4.8.1.nupkg");

        var compiledScriptPath = await CompileScriptToOutput(sourceRoot, outputRoot, scriptPath);
        var generatedScript = await File.ReadAllTextAsync(compiledScriptPath);

        // Verify at least 4 non-root embedded module entries exist
        var moduleEntryCount = generatedScript.Split(["Name = '"], StringSplitOptions.None).Length - 1;
        // Exclude root script (first entry), ensure remaining ≥ 4
        var nonRootModuleCount = moduleEntryCount - 1;

        var results = await RunPwshConcurrently(compiledScriptPath, 4, programDataRoot, tempRoot);
        var modulesRoot = GetModulesRoot(programDataRoot, results);

        // Verify .ready for all expected modules
        var moduleADirResolved = FindSingleModuleDirectory(modulesRoot, "ModuleA-");
        var moduleBDirResolved = FindSingleModuleDirectory(modulesRoot, "ModuleB-");
        var utilityDirResolved = FindSingleModuleDirectory(modulesRoot, "Utility-");
        var psReadLineDirResolved = FindSingleModuleDirectory(modulesRoot, "PSReadLine-");
        var pkgMgmtDirResolved = FindSingleModuleDirectory(modulesRoot, "PackageManagement-");

        Assert.Multiple(() => {
            Assert.That(results, Has.Length.EqualTo(4));
            Assert.That(results.All(result => result.ExitCode == 0), Is.True, FormatResults(results));
            Assert.That(results.All(result => result.StandardOutput.Contains("Utility-Result:B-A-Value", StringComparison.Ordinal)), Is.True, FormatResults(results));
            Assert.That(results.All(result => result.StandardOutput.Contains("Logged: All-Exports-Work", StringComparison.Ordinal)), Is.True, FormatResults(results));
            Assert.That(results.All(result => result.StandardError.Contains("PSReadLine-B8EE4D", StringComparison.Ordinal) is false), Is.True, FormatResults(results));
            Assert.That(results.All(result => result.StandardError.Contains("PackageManagement-", StringComparison.Ordinal) is false), Is.True, FormatResults(results));
            Assert.That(nonRootModuleCount, Is.GreaterThanOrEqualTo(4), $"Expected ≥4 embedded non-root modules, found {nonRootModuleCount}.");
            Assert.That(File.Exists(Path.Combine(moduleADirResolved, ".ready")), Is.True);
            Assert.That(File.Exists(Path.Combine(moduleBDirResolved, ".ready")), Is.True);
            Assert.That(File.Exists(Path.Combine(utilityDirResolved, ".ready")), Is.True);
            Assert.That(File.Exists(Path.Combine(psReadLineDirResolved, ".ready")), Is.True);
            Assert.That(File.Exists(Path.Combine(pkgMgmtDirResolved, ".ready")), Is.True);
            Assert.That(Directory.GetFiles(modulesRoot, "*.lock", SearchOption.TopDirectoryOnly), Is.Empty);
        });
    });

    [Test]
    public async Task GeneratedScript_WhenReadyMarkerMissingButModuleExists_RebuildsUtf8Module() => await InvokeWithInjectedModuleOptOut(async () => {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var outputRoot = TestUtils.GenerateUniqueDirectory();
        var programDataRoot = TestUtils.GenerateUniqueDirectory();
        var tempRoot = TestUtils.GenerateUniqueDirectory();

        var childPath = Path.Combine(sourceRoot, "Child.psm1");
        var scriptPath = Path.Combine(sourceRoot, "Root.ps1");
        await File.WriteAllTextAsync(childPath, "function Invoke-Child { 'Rebuilt-Child' }");
        await File.WriteAllTextAsync(scriptPath, "using module ./Child.psm1\nInvoke-Child");

        var compiledScriptPath = await CompileScriptToOutput(sourceRoot, outputRoot, scriptPath);
        var generatedScript = await File.ReadAllTextAsync(compiledScriptPath);
        var nameHash = ExtractNameHash(generatedScript, "Child");
        var modulesRoot = GetModulesRootForPwsh(programDataRoot);

        Directory.CreateDirectory(modulesRoot);

        var moduleDirectory = Path.Combine(modulesRoot, nameHash);
        Directory.CreateDirectory(moduleDirectory);
        var moduleFile = Path.Combine(moduleDirectory, $"{nameHash}.psm1");
        var staleContent = "function Invoke-Child { throw 'stale' }";
        if (GetPwshMajorVersion() >= 6) {
            await File.WriteAllBytesAsync(moduleFile, [.. new byte[] { 0xEF, 0xBB, 0xBF }, .. Encoding.UTF8.GetBytes(staleContent)]);
        } else {
            await File.WriteAllTextAsync(moduleFile, staleContent, new UTF8Encoding(false));
        }

        var result = await RunPwsh(compiledScriptPath, programDataRoot, tempRoot);
        var rebuiltContent = await File.ReadAllTextAsync(moduleFile);

        Assert.Multiple(() => {
            Assert.That(result.ExitCode, Is.EqualTo(0), FormatResult(result));
            Assert.That(result.StandardOutput, Does.Contain("Rebuilt-Child"));
            Assert.That(File.Exists(Path.Combine(moduleDirectory, ".ready")), Is.True);
            Assert.That(rebuiltContent, Does.Contain("Rebuilt-Child"));
            Assert.That(rebuiltContent, Does.Not.Contain("throw 'stale'"));
        });
    });

    [Test]
    public async Task GeneratedScript_CompleteModuleLock_LeavesZipFolderUnreadyOnFailedOperation() => await InvokeWithInjectedModuleOptOut(async () => {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var outputRoot = TestUtils.GenerateUniqueDirectory();
        var programDataRoot = TestUtils.GenerateUniqueDirectory();
        var tempRoot = TestUtils.GenerateUniqueDirectory();
        var scriptPath = Path.Combine(sourceRoot, "Root.ps1");
        await File.WriteAllTextAsync(scriptPath, "Write-Output 'noop'");

        var compiledScriptPath = await CompileScriptToOutput(sourceRoot, outputRoot, scriptPath);
        var moduleDirectory = Path.Combine(tempRoot, "zip-lock-test-module");
        Directory.CreateDirectory(moduleDirectory);

        await File.WriteAllTextAsync(Path.Combine(moduleDirectory, "partial.txt"), "partial");

        var harnessPath = Path.Combine(tempRoot, "complete-module-lock-test.ps1");
        var harness = @"
$ErrorActionPreference = 'Stop'
$env:COMPILED_NO_RUN = 'true'
. @SCRIPT_PATH@
$moduleDir = @MODULE_DIR@
$readyPath = Join-Path $moduleDir '.ready'
$lockPath = Join-Path $moduleDir '.lock'
Set-Content -Path $lockPath -Value '' -NoNewline
Complete-ModuleLock -LockPath $lockPath -ReadyPath $readyPath -ModuleFolderPath $moduleDir -ModuleType 'Zip' -OperationSucceeded:$false | Out-Null
if (Test-Path $readyPath) { throw '.ready created after failed operation' }
";
        harness = harness.Replace("@SCRIPT_PATH@", "'" + compiledScriptPath.Replace("'", "''") + "'");
        harness = harness.Replace("@MODULE_DIR@", "'" + moduleDirectory.Replace("'", "''") + "'");
        await File.WriteAllTextAsync(harnessPath, harness);

        var processResult = await RunPwsh(harnessPath, programDataRoot, tempRoot);

        Assert.Multiple(() => {
            Assert.That(processResult.ExitCode, Is.EqualTo(0), FormatResult(processResult));
            Assert.That(File.Exists(Path.Combine(moduleDirectory, ".ready")), Is.False);
            Assert.That(File.Exists(Path.Combine(moduleDirectory, "partial.txt")), Is.True);
        });
    });

    [Test]
    public async Task GeneratedScript_WhenReadyMarkerExistsButZipFolderEmpty_RebuildsModule() => await InvokeWithInjectedModuleOptOut(async () => {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var outputRoot = TestUtils.GenerateUniqueDirectory();
        var programDataRoot = TestUtils.GenerateUniqueDirectory();
        var tempRoot = TestUtils.GenerateUniqueDirectory();
        var commonDir = Path.Combine(sourceRoot, "common");
        Directory.CreateDirectory(commonDir);

        var loggingPath = Path.Combine(commonDir, "Logging.psm1");
        var scriptPath = Path.Combine(sourceRoot, "Root.ps1");

        await File.WriteAllTextAsync(loggingPath, "using module @{ ModuleName = 'PSReadLine'; RequiredVersion = '2.3.5' }\nfunction Invoke-Info { param([string]$Message) $Message }");
        await File.WriteAllTextAsync(scriptPath, "using module ./common/Logging.psm1\nInvoke-Info 'Zip-Rebuilt'");

        await EnsureRemotePackageCached("PSReadLine", "2.3.5", "PSReadLine.2.3.5.nupkg");

        var compiledScriptPath = await CompileScriptToOutput(sourceRoot, outputRoot, scriptPath);
        var generatedScript = await File.ReadAllTextAsync(compiledScriptPath);
        var nameHash = ExtractNameHash(generatedScript, "PSReadLine");
        var modulesRoot = GetModulesRootForPwsh(programDataRoot);

        Directory.CreateDirectory(modulesRoot);

        var moduleDirectory = Path.Combine(modulesRoot, nameHash);
        Directory.CreateDirectory(moduleDirectory);
        await File.WriteAllTextAsync(Path.Combine(moduleDirectory, ".ready"), "stale");

        var result = await RunPwsh(compiledScriptPath, programDataRoot, tempRoot);
        var extractedFiles = Directory.GetFiles(moduleDirectory, "*", SearchOption.AllDirectories)
            .Where(path => !path.EndsWith(".ready", StringComparison.Ordinal))
            .ToArray();

        Assert.Multiple(() => {
            Assert.That(result.ExitCode, Is.EqualTo(0), FormatResult(result));
            Assert.That(result.StandardOutput, Does.Contain("Zip-Rebuilt"));
            Assert.That(File.Exists(Path.Combine(moduleDirectory, ".ready")), Is.True);
            Assert.That(extractedFiles, Is.Not.Empty);
            Assert.That(extractedFiles.Any(path => Path.GetFileName(path).StartsWith("PSReadLine-", StringComparison.OrdinalIgnoreCase) && path.EndsWith(".psd1", StringComparison.OrdinalIgnoreCase)), Is.True);
        });
    });

    [Test]
    public async Task GeneratedScript_WithWrapper_CapturesNonTerminatingErrors() => await InvokeWithInjectedModuleOptOut(async () => {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var outputRoot = TestUtils.GenerateUniqueDirectory();
        var programDataRoot = TestUtils.GenerateUniqueDirectory();
        var tempRoot = TestUtils.GenerateUniqueDirectory();

        var scriptPath = Path.Combine(sourceRoot, "Root.ps1");
        await File.WriteAllTextAsync(scriptPath, "Write-Error 'captured-non-terminating'\n'done'");

        var compiledScriptPath = await CompileScriptToOutput(sourceRoot, outputRoot, scriptPath);
        var result = await RunPwsh(compiledScriptPath, programDataRoot, tempRoot, useCompiledJob: true);

        Assert.Multiple(() => {
            Assert.That(result.ExitCode, Is.EqualTo(0), FormatResult(result));
            Assert.That(result.StandardError, Does.Contain("captured-non-terminating"));
        });
    });

    [Test]
    public async Task GeneratedScript_WithWrapper_PassesThroughMixedOutput() => await InvokeWithInjectedModuleOptOut(async () => {
        // Regression: wrapper must correctly multiplex stdout (1), info stream (6),
        // and captured non-terminating errors (2) in a single run.
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var outputRoot = TestUtils.GenerateUniqueDirectory();
        var programDataRoot = TestUtils.GenerateUniqueDirectory();
        var tempRoot = TestUtils.GenerateUniqueDirectory();

        var scriptPath = Path.Combine(sourceRoot, "Root.ps1");
        await File.WriteAllTextAsync(scriptPath, @"'stdout-msg'
Write-Information 'info-msg' -InformationAction Continue
Write-Error 'err-msg'"
);

        var compiledScriptPath = await CompileScriptToOutput(sourceRoot, outputRoot, scriptPath);
        var result = await RunPwsh(compiledScriptPath, programDataRoot, tempRoot, useCompiledJob: true);

        Assert.Multiple(() => {
            Assert.That(result.ExitCode, Is.EqualTo(0), FormatResult(result));
            Assert.That(result.StandardOutput, Does.Contain("stdout-msg"), "stdout line must appear in stdout.");
            Assert.That(result.StandardOutput, Does.Contain("info-msg"), "info stream goes to stdout in child process.");
            Assert.That(result.StandardError, Does.Contain("err-msg"), "non-terminating Write-Error must appear in stderr.");
        });
    });

    [Test]
    public async Task GeneratedScript_WithWrapper_CapturesTaggedInfoStreamError() => await InvokeWithInjectedModuleOptOut(async () => {
        // Regression: Invoke-Error -> Write-Information with tag 'AMT.ErrorDisplay' via info stream 6.
        // Wrapper did only 2>&1, missing stream 6. Fix: 6>&1 + capture tagged info records.
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var outputRoot = TestUtils.GenerateUniqueDirectory();
        var programDataRoot = TestUtils.GenerateUniqueDirectory();
        var tempRoot = TestUtils.GenerateUniqueDirectory();

        var commonDir = Path.Combine(sourceRoot, "common");
        Directory.CreateDirectory(commonDir);
        var loggingPath = Path.Combine(commonDir, "Logging.psm1");
        await File.WriteAllTextAsync(loggingPath, @"
using module @{ ModuleName = 'PSReadLine'; RequiredVersion = '2.3.5' }

function Invoke-Write {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$PSMessage,
        [string]$PSPrefix,
        [string]$PSColour,
        [bool]$ShouldWrite = $true,
        [string]$InformationTag
    )
    if (-not $ShouldWrite) { return }
    $msg = if ($PSPrefix) { ""$PSPrefix $PSMessage"" } else { $PSMessage }
    $InformationPreference = 'Continue'
    if ($InformationTag) {
        Write-Information $msg -Tags $InformationTag
    } else {
        Write-Information $msg
    }
}

function Invoke-Error {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Message,
        [string]$UnicodePrefix,
        [switch]$Throw,
        [System.Management.Automation.ErrorCategory]$ErrorCategory = [System.Management.Automation.ErrorCategory]::NotSpecified,
        [System.Management.Automation.InvocationInfo]$Caller,
        [System.Management.Automation.PSCmdlet]$CallerCmdlet
    )
    if ($Throw) {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new($Message),
            'Error',
            $ErrorCategory,
            $Caller
        )
        $Cmdlet = if ($CallerCmdlet) { $CallerCmdlet } else { $PSCmdlet }
        $Cmdlet.ThrowTerminatingError($ErrorRecord)
    } else {
        Invoke-Write -PSPrefix '\u274c' -PSMessage $Message -PSColour 'Red' -ShouldWrite $true -InformationTag 'AMT.ErrorDisplay'
    }
}

Export-ModuleMember -Function Invoke-Write, Invoke-Error
".TrimStart());

        var scriptPath = Path.Combine(sourceRoot, "Root.ps1");
        await File.WriteAllTextAsync(scriptPath, @"using module ./common/Logging.psm1
Invoke-Error 'tagged-info-stream-err'
'done'".TrimStart());

        await EnsureRemotePackageCached("PSReadLine", "2.3.5", "PSReadLine.2.3.5.nupkg");

        var compiledScriptPath = await CompileScriptToOutput(sourceRoot, outputRoot, scriptPath);
        var result = await RunPwsh(compiledScriptPath, programDataRoot, tempRoot, useCompiledJob: true);

        Assert.Multiple(() => {
            Assert.That(result.ExitCode, Is.EqualTo(0), FormatResult(result));
            Assert.That(result.StandardError, Does.Contain("tagged-info-stream-err"),
                "Tagged info-stream error from Invoke-Error must appear in stderr.");
        });
    });

    [Test]
    public async Task GeneratedScript_WithWrapper_CapturesTaggedInfoStreamTerminatingError() => await InvokeWithInjectedModuleOptOut(async () => {
        // Regression: Invoke-Error -Throw goes to error stream 2, caught by wrapper try/catch.
        // Wrapper must re-emit the terminating error text into stderr.
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var outputRoot = TestUtils.GenerateUniqueDirectory();
        var programDataRoot = TestUtils.GenerateUniqueDirectory();
        var tempRoot = TestUtils.GenerateUniqueDirectory();

        var commonDir = Path.Combine(sourceRoot, "common");
        Directory.CreateDirectory(commonDir);
        var loggingPath = Path.Combine(commonDir, "Logging.psm1");
        await File.WriteAllTextAsync(loggingPath, @"
using module @{ ModuleName = 'PSReadLine'; RequiredVersion = '2.3.5' }

function Invoke-Write {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$PSMessage,
        [string]$PSPrefix,
        [string]$PSColour,
        [bool]$ShouldWrite = $true,
        [string]$InformationTag
    )
    if (-not $ShouldWrite) { return }
    $msg = if ($PSPrefix) { ""$PSPrefix $PSMessage"" } else { $PSMessage }
    $InformationPreference = 'Continue'
    if ($InformationTag) {
        Write-Information $msg -Tags $InformationTag
    } else {
        Write-Information $msg
    }
}

function Invoke-Error {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Message,
        [string]$UnicodePrefix,
        [switch]$Throw,
        [System.Management.Automation.ErrorCategory]$ErrorCategory = [System.Management.Automation.ErrorCategory]::NotSpecified,
        [System.Management.Automation.InvocationInfo]$Caller,
        [System.Management.Automation.PSCmdlet]$CallerCmdlet
    )
    if ($Throw) {
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new($Message),
            'Error',
            $ErrorCategory,
            $Caller
        )
        $Cmdlet = if ($CallerCmdlet) { $CallerCmdlet } else { $PSCmdlet }
        $Cmdlet.ThrowTerminatingError($ErrorRecord)
    } else {
        Invoke-Write -PSPrefix '\u274c' -PSMessage $Message -PSColour 'Red' -ShouldWrite $true -InformationTag 'AMT.ErrorDisplay'
    }
}

Export-ModuleMember -Function Invoke-Write, Invoke-Error
".TrimStart());

        var scriptPath = Path.Combine(sourceRoot, "Root.ps1");
        await File.WriteAllTextAsync(scriptPath, @"using module ./common/Logging.psm1
Invoke-Error 'tagged-info-stream-term-err' -Throw
'done'".TrimStart());

        await EnsureRemotePackageCached("PSReadLine", "2.3.5", "PSReadLine.2.3.5.nupkg");

        var compiledScriptPath = await CompileScriptToOutput(sourceRoot, outputRoot, scriptPath);
        var result = await RunPwsh(compiledScriptPath, programDataRoot, tempRoot, useCompiledJob: true);

        Assert.Multiple(() => {
            Assert.That(result.ExitCode, Is.EqualTo(0), FormatResult(result));
            Assert.That(result.StandardError, Does.Contain("tagged-info-stream-term-err"),
                "Terminating error from Invoke-Error -Throw must appear in stderr.");
        });
    });

    [Test]
    public async Task GeneratedScript_WithWrapper_CapturesTerminatingErrorDetail() => await InvokeWithInjectedModuleOptOut(async () => {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var outputRoot = TestUtils.GenerateUniqueDirectory();
        var programDataRoot = TestUtils.GenerateUniqueDirectory();
        var tempRoot = TestUtils.GenerateUniqueDirectory();

        var scriptPath = Path.Combine(sourceRoot, "Root.ps1");
        await File.WriteAllTextAsync(scriptPath, "throw 'boom-terminating'");

        var compiledScriptPath = await CompileScriptToOutput(sourceRoot, outputRoot, scriptPath);
        var result = await RunPwsh(compiledScriptPath, programDataRoot, tempRoot, useCompiledJob: true);

        Assert.Multiple(() => {
            Assert.That(result.ExitCode, Is.EqualTo(0), FormatResult(result));
            Assert.That(result.StandardError, Does.Contain("boom-terminating"));
            Assert.That(result.StandardError, Does.Not.Contain("Caught terminating error"));
        });
    });

    [Test]
    public async Task GeneratedScript_UnicodeLocalModulePreservesOutputAndExtractedBytes() => await InvokeWithInjectedModuleOptOut(async () => {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var outputRoot = TestUtils.GenerateUniqueDirectory();
        var programDataRoot = TestUtils.GenerateUniqueDirectory();
        var tempRoot = TestUtils.GenerateUniqueDirectory();

        var moduleDir = Path.Combine(sourceRoot, "Unicode");
        Directory.CreateDirectory(moduleDir);
        var modulePath = Path.Combine(moduleDir, "Unicode.psm1");
        var scriptPath = Path.Combine(sourceRoot, "Root.ps1");

        var moduleContent = @"
function Get-UnicodePayload {
    [CmdletBinding()]
    param()
    '📦-🗑️-🔄-Ω'
}
Export-ModuleMember -Function Get-UnicodePayload
".TrimStart();
        await File.WriteAllTextAsync(modulePath, moduleContent);
        await File.WriteAllTextAsync(scriptPath, "using module ./Unicode/Unicode.psm1\nGet-UnicodePayload");

        var compiledScriptPath = await CompileScriptToOutput(sourceRoot, outputRoot, scriptPath);
        var generatedScript = await File.ReadAllTextAsync(compiledScriptPath);
        var result = await RunPwsh(compiledScriptPath, programDataRoot, tempRoot);
        var modulesRoot = GetModulesRoot(programDataRoot, [result]);
        var moduleDirectory = FindSingleModuleDirectory(modulesRoot, "Unicode-");
        var moduleFile = Directory.GetFiles(moduleDirectory, "Unicode-*.psm1", SearchOption.TopDirectoryOnly).Single();
        var extractedBytes = await File.ReadAllBytesAsync(moduleFile);
        var extractedText = Encoding.UTF8.GetString(extractedBytes);

        Assert.Multiple(() => {
            Assert.That(result.ExitCode, Is.EqualTo(0), FormatResult(result));
            Assert.That(result.StandardOutput, Does.Contain("📦-🗑️-🔄-Ω"));
            Assert.That(generatedScript, Does.Not.Contain("📦"));
            Assert.That(generatedScript, Does.Not.Contain("🗑️"));
            Assert.That(generatedScript, Does.Not.Contain("🔄"));
            Assert.That(generatedScript, Does.Not.Contain("Ω"));
            Assert.That(generatedScript, Is.EqualTo(Encoding.ASCII.GetString(Encoding.ASCII.GetBytes(generatedScript))));
            Assert.That(generatedScript, Does.Match("['\"]?[A-Za-z0-9+/=]+['\"]?"));
            Assert.That(extractedText, Does.Contain("📦-🗑️-🔄-Ω"));
        });
    });

    [Test]
    public async Task GeneratedScript_UnicodeLocalModulePreservesOutputAndExtractedBytes() => await InvokeWithInjectedModuleOptOut(async () => {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var outputRoot = TestUtils.GenerateUniqueDirectory();
        var programDataRoot = TestUtils.GenerateUniqueDirectory();
        var tempRoot = TestUtils.GenerateUniqueDirectory();

        var moduleDir = Path.Combine(sourceRoot, "Unicode");
        Directory.CreateDirectory(moduleDir);
        var modulePath = Path.Combine(moduleDir, "Unicode.psm1");
        var scriptPath = Path.Combine(sourceRoot, "Root.ps1");

        var moduleContent = @"
function Get-UnicodePayload {
    [CmdletBinding()]
    param()
    '📦-🗑️-🔄-Ω'
}
Export-ModuleMember -Function Get-UnicodePayload
".TrimStart();
        await File.WriteAllTextAsync(modulePath, moduleContent);
        await File.WriteAllTextAsync(scriptPath, "using module ./Unicode/Unicode.psm1\nGet-UnicodePayload");

        var compiledScriptPath = await CompileScriptToOutput(sourceRoot, outputRoot, scriptPath);
        var generatedScript = await File.ReadAllTextAsync(compiledScriptPath);
        var result = await RunPwsh(compiledScriptPath, programDataRoot, tempRoot);
        var modulesRoot = GetModulesRoot(programDataRoot, [result]);
        var moduleDirectory = FindSingleModuleDirectory(modulesRoot, "Unicode-");
        var moduleFile = Directory.GetFiles(moduleDirectory, "Unicode-*.psm1", SearchOption.TopDirectoryOnly).Single();
        var extractedBytes = await File.ReadAllBytesAsync(moduleFile);
        var extractedText = Encoding.UTF8.GetString(extractedBytes);

        Assert.Multiple(() => {
            Assert.That(result.ExitCode, Is.EqualTo(0), FormatResult(result));
            Assert.That(result.StandardOutput, Does.Contain("📦-🗑️-🔄-Ω"));
            Assert.That(generatedScript, Does.Not.Contain("📦"));
            Assert.That(generatedScript, Does.Not.Contain("🗑️"));
            Assert.That(generatedScript, Does.Not.Contain("🔄"));
            Assert.That(generatedScript, Does.Not.Contain("Ω"));
            Assert.That(generatedScript, Does.Contain("Compression = 'GZip'"));
            Assert.That(generatedScript, Does.Contain("Type = 'UTF8String'"));
            Assert.That(generatedScript, Is.EqualTo(Encoding.ASCII.GetString(Encoding.ASCII.GetBytes(generatedScript))));
            Assert.That(generatedScript, Does.Match("['\"]?[A-Za-z0-9+/=]+['\"]?"));
            Assert.That(extractedText, Does.Contain("📦-🗑️-🔄-Ω"));
        });
    });

    [Test]
    public async Task GeneratedScript_LocalTextPayloadUsesGzipAndRunsEndToEnd() => await InvokeWithInjectedModuleOptOut(async () => {
        var sourceRoot = TestUtils.GenerateUniqueDirectory();
        var outputRoot = TestUtils.GenerateUniqueDirectory();
        var programDataRoot = TestUtils.GenerateUniqueDirectory();
        var tempRoot = TestUtils.GenerateUniqueDirectory();

        var moduleDir = Path.Combine(sourceRoot, "Text");
        Directory.CreateDirectory(moduleDir);
        var modulePath = Path.Combine(moduleDir, "Text.psm1");
        var scriptPath = Path.Combine(sourceRoot, "Root.ps1");

        var moduleContent = @"
function Get-LocalTextPayload {
    [CmdletBinding()]
    param()
    'gzip local text payload'
}
Export-ModuleMember -Function Get-LocalTextPayload
".TrimStart();
        await File.WriteAllTextAsync(modulePath, moduleContent);
        await File.WriteAllTextAsync(scriptPath, "using module ./Text/Text.psm1\nGet-LocalTextPayload");

        var compiledScriptPath = await CompileScriptToOutput(sourceRoot, outputRoot, scriptPath);
        var generatedScript = await File.ReadAllTextAsync(compiledScriptPath);
        var result = await RunPwsh(compiledScriptPath, programDataRoot, tempRoot);
        var modulesRoot = GetModulesRoot(programDataRoot, [result]);
        var moduleDirectory = FindSingleModuleDirectory(modulesRoot, "Text-");
        var moduleFile = Directory.GetFiles(moduleDirectory, "Text-*.psm1", SearchOption.TopDirectoryOnly).Single();
        var extractedText = await File.ReadAllTextAsync(moduleFile);

        Assert.Multiple(() => {
            Assert.That(result.ExitCode, Is.EqualTo(0), FormatResult(result));
            Assert.That(result.StandardOutput, Does.Contain("gzip local text payload"));
            Assert.That(generatedScript, Does.Contain("Compression = 'GZip'"));
            Assert.That(generatedScript, Does.Contain("Type = 'UTF8String'"));
            Assert.That(generatedScript, Does.Not.Contain("Compression = 'None'"));
            Assert.That(extractedText, Does.Contain("gzip local text payload"));
        });
    });

    [Test]
    public async Task GeneratedScript_LocalTextPayloadUsesNoneModeEndToEnd() => await InvokeWithInjectedModuleOptOut(async () => {
        var previousCompression = CompilerSettings.EmbeddedLocalTextCompression;
        var previousLevel = CompilerSettings.EmbeddedLocalTextCompressionLevel;
        CompilerSettings.ConfigureEmbeddedLocalTextCompression("none");
        try {
            var sourceRoot = TestUtils.GenerateUniqueDirectory();
            var outputRoot = TestUtils.GenerateUniqueDirectory();
            var programDataRoot = TestUtils.GenerateUniqueDirectory();
            var tempRoot = TestUtils.GenerateUniqueDirectory();

            var moduleDir = Path.Combine(sourceRoot, "Text");
            Directory.CreateDirectory(moduleDir);
            var modulePath = Path.Combine(moduleDir, "Text.psm1");
            var scriptPath = Path.Combine(sourceRoot, "Root.ps1");

            var moduleContent = @"
function Get-LocalTextPayload {
    [CmdletBinding()]
    param()
    'none local text payload'
}
Export-ModuleMember -Function Get-LocalTextPayload
".TrimStart();
            await File.WriteAllTextAsync(modulePath, moduleContent);
            await File.WriteAllTextAsync(scriptPath, "using module ./Text/Text.psm1\nGet-LocalTextPayload");

            var compiledScriptPath = await CompileScriptToOutput(sourceRoot, outputRoot, scriptPath);
            var generatedScript = await File.ReadAllTextAsync(compiledScriptPath);
            var result = await RunPwsh(compiledScriptPath, programDataRoot, tempRoot);

            Assert.Multiple(() => {
                Assert.That(result.ExitCode, Is.EqualTo(0), FormatResult(result));
                Assert.That(result.StandardOutput, Does.Contain("none local text payload"));
                Assert.That(generatedScript, Does.Contain("Compression = 'None'"));
                Assert.That(generatedScript, Does.Contain("Type = 'UTF8String'"));
                Assert.That(generatedScript, Does.Not.Contain("Compression = 'GZip'"));
            });
        } finally {
            CompilerSettings.EmbeddedLocalTextCompression = previousCompression;
            CompilerSettings.EmbeddedLocalTextCompressionLevel = previousLevel;
        }
    });

    private static async Task InvokeWithInjectedModuleOptOut(Func<Task> action) {
        var previous = Environment.GetEnvironmentVariable("COMPILER_SKIP_INJECTED_MODULES");
        Environment.SetEnvironmentVariable("COMPILER_SKIP_INJECTED_MODULES", bool.TrueString);
        try {
            await action();
        } finally {
            Environment.SetEnvironmentVariable("COMPILER_SKIP_INJECTED_MODULES", previous);
        }
    }

    private static async Task<string> CompileScriptToOutput(string sourceRoot, string outputRoot, string scriptPath) {

        var parent = new ResolvableParent(sourceRoot);

        var scriptSpec = new PathedModuleSpec(sourceRoot, scriptPath);
        var script = (await Resolvable.TryCreateScript(scriptSpec, parent)).Unwrap();

        CompiledScript? compiled = null;
        parent.QueueResolve(script, compiledScript => {
            compiled = compiledScript;
            return Task.CompletedTask;
        });
        await parent.Compile();

        Assert.That(compiled, Is.Not.Null);
        var output = compiled!.GetPowerShellObject().Unwrap();
        await Program.Output(sourceRoot, outputRoot, scriptPath, output, true);
        return Program.GetOutputLocation(sourceRoot, outputRoot, scriptPath);
    }

    private static async Task EnsureRemotePackageCached(string moduleName, string version, string resourceName) {
        var cachePath = Path.Join(Path.GetTempPath(), "PowerShellGet", moduleName);
        Directory.CreateDirectory(cachePath);
        var nupkgPath = Path.Join(cachePath, $"{moduleName}.{version}.nupkg");
        if (File.Exists(nupkgPath)) {
            return;
        }

        var info = typeof(ScriptTemplateRuntimeTests).Assembly.GetName();
        var resource = $"{info.Name}.Resources.{resourceName}";
        await using var stream = typeof(ScriptTemplateRuntimeTests).Assembly.GetManifestResourceStream(resource)!;
        await using var file = File.Create(nupkgPath);
        await stream.CopyToAsync(file);
    }

    private static string GetModulesRoot(string programDataRoot) {
        var modulesParent = Path.Combine(programDataRoot, "AMT", "PowerShell", "Modules");
        Directory.CreateDirectory(modulesParent);
        var existing = Directory.GetDirectories(modulesParent, "PS*", SearchOption.TopDirectoryOnly).SingleOrDefault();
        return existing ?? GetModulesRootForPwsh(programDataRoot);
    }

    private static string GetModulesRootForPwsh(string programDataRoot) {
        var modulesParent = Path.Combine(programDataRoot, "AMT", "PowerShell", "Modules");
        Directory.CreateDirectory(modulesParent);
        return Path.Combine(modulesParent, $"PS{GetPwshMajorVersion()}");
    }

    private static string GetModulesRoot(string programDataRoot, IEnumerable<ProcessResult> results) {
        var modulesRoot = GetModulesRoot(programDataRoot);
        if (Directory.Exists(modulesRoot)) {
            return modulesRoot;
        }

        var details = FormatResults(results);
        Assert.Fail($"Module root was not created under '{programDataRoot}'.{Environment.NewLine}{details}");
        return modulesRoot;
    }

    private static string FindSingleModuleDirectory(string modulesRoot, string prefix) {
        var matches = Directory.GetDirectories(modulesRoot, $"{prefix}*", SearchOption.TopDirectoryOnly);
        Assert.That(matches, Has.Length.EqualTo(1), $"Expected exactly one module directory matching '{prefix}' in '{modulesRoot}'.");
        return matches[0];
    }

    private static string ExtractNameHash(string generatedScript, string moduleName) {
        var marker = $"Name = '{moduleName}'";
        var markerIndex = generatedScript.IndexOf(marker, StringComparison.Ordinal);
        Assert.That(markerIndex, Is.GreaterThanOrEqualTo(0), $"Could not find embedded module '{moduleName}'.");

        var hashMarker = "Hash = '";
        var hashIndex = generatedScript.IndexOf(hashMarker, markerIndex, StringComparison.Ordinal);
        Assert.That(hashIndex, Is.GreaterThanOrEqualTo(0), $"Could not find hash for embedded module '{moduleName}'.");
        hashIndex += hashMarker.Length;

        var hashEnd = generatedScript.IndexOf('\'', hashIndex);
        Assert.That(hashEnd, Is.GreaterThan(hashIndex), $"Could not parse hash for embedded module '{moduleName}'.");
        var hash = generatedScript[hashIndex..hashEnd];
        return $"{moduleName}-{hash}";
    }

    private static async Task<ProcessResult[]> RunPwshConcurrently(string scriptPath, int count, string programDataRoot, string tempRoot) {
        var tasks = Enumerable.Range(0, count)
            .Select(_ => RunPwsh(scriptPath, programDataRoot, tempRoot))
            .ToArray();

        return await Task.WhenAll(tasks);
    }

    private static async Task<ProcessResult> RunPwsh(string scriptPath, string programDataRoot, string tempRoot, bool useCompiledJob = false) {
        Directory.CreateDirectory(programDataRoot);
        Directory.CreateDirectory(tempRoot);

        var startInfo = new ProcessStartInfo {
            FileName = "pwsh",
            Arguments = $"-NoProfile -File \"{scriptPath}\"",

            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = Path.GetDirectoryName(scriptPath)
        };

        startInfo.Environment["ProgramData"] = programDataRoot;
        startInfo.Environment["TEMP"] = tempRoot;
        startInfo.Environment["TMP"] = tempRoot;
        if (!useCompiledJob) {
            startInfo.Environment["COMPILED_NO_JOB"] = bool.TrueString;
        }

        using var process = new Process { StartInfo = startInfo };
        process.Start();

        var standardOutput = await process.StandardOutput.ReadToEndAsync();
        var standardError = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();

        return new ProcessResult(process.ExitCode, standardOutput, standardError);
    }

    private static int GetPwshMajorVersion() {
        var startInfo = new ProcessStartInfo {
            FileName = "pwsh",
            Arguments = "-NoProfile -Command \"$PSVersionTable.PSVersion.Major\"",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var process = new Process { StartInfo = startInfo };
        process.Start();
        var standardOutput = process.StandardOutput.ReadToEnd().Trim();
        var standardError = process.StandardError.ReadToEnd().Trim();
        process.WaitForExit();

        Assert.That(process.ExitCode, Is.EqualTo(0), $"Failed to query pwsh version.{Environment.NewLine}{standardError}");
        return int.Parse(standardOutput, CultureInfo.InvariantCulture);
    }

    private static string FormatResults(IEnumerable<ProcessResult> results) => string.Join(Environment.NewLine + "---" + Environment.NewLine, results.Select(FormatResult));

    private static string FormatResult(ProcessResult result) => $"ExitCode: {result.ExitCode}{Environment.NewLine}STDOUT:{Environment.NewLine}{result.StandardOutput}{Environment.NewLine}STDERR:{Environment.NewLine}{result.StandardError}";
}
