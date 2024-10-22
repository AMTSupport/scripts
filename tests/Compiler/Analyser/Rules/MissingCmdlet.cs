// Copyright (c) James Draycott. All Rights Reserved.
// Licensed under the GPL3 License, See LICENSE in the project root for license information.

using Compiler.Analyser.Rules;
using static LanguageExt.Prelude;

namespace Compiler.Test.Analyser.Rules;

[TestFixture]
public class MissingCmdletTests {
    [TestCaseSource(typeof(Data), nameof(Data.TestCases))]
    public bool Test(string script) {
        var visitor = new RuleVisitor([new MissingCmdlet()], []);
        var ast = AstHelper.GetAstReportingErrors(script, None, [], out _).Unwrap();
        visitor.DefaultVisit(ast);
        return visitor.Issues.Count > 0;
    }

    private static class Data {
        public static IEnumerable<TestCaseData> TestCases {
            get {
                yield return new TestCaseData("""
                #Requires -Version 5.1

                Using module ../common/Environment.psm1
                Using module ../common/Logging.psm1
                Using module ../common/Exit.psm1
                Using module ../common/Ensure.psm1

                Using namespace Microsoft.BitLocker.Structures

                #region - Error Codes
                $Script:ERROR_BITLOCKER_DISABLED = Register-ExitCode 'BitLocker is not enabled on the system drive.';
                $Script:ERROR_NO_RECOVERY_PASSWORD = Register-ExitCode 'BitLocker is not configured to use a recovery password.';
                $Script:ERROR_DURING_UPLOAD = Register-ExitCode 'An error occurred while uploading the recovery key to Azure AD.';
                #endregion - Error Codes

                Invoke-RunMain $PSCmdlet {
                    Invoke-EnsureAdministrator;

                    # Safety: This should never have a null value, as we are using the system drive environment variable.
                    [BitLockerVolume]$Local:Volume = Get-BitLockerVolume -MountPoint $env:SystemDrive;
                    [BitLockerVolumeKeyProtector]$Local:RecoveryProtector = ($Local:Volume.KeyProtector | Where-Object { $_.KeyProtectorType -eq [Microsoft.BitLocker.Structures.BitLockerVolumeKeyProtectorType]::RecoveryPassword });

                    if (($Local:Volume.ProtectionStatus -eq 'Off') -or $Local:Volume.KeyProtector.Count -eq 0) {
                        Invoke-FailedExit -ExitCode $Script:ERROR_BITLOCKER_DISABLED;
                    }

                    if ($null -eq $Local:RecoveryProtector) {
                        Invoke-FailedExit -ExitCode $Script:ERROR_NO_RECOVERY_PASSWORD;
                    }

                    try {
                        BackupToAAD-BitLockerKeyProtector -MountPoint $env:SystemDrive -KeyProtectorId $Local:RecoveryProtector.KeyProtectorID | Out-Null;
                        Invoke-Info 'BitLocker recovery key successfully backed up to Azure AD.';
                    } catch {
                        Invoke-FailedExit -ErrorRecord $_ -ExitCode $Script:ERROR_DURING_UPLOAD;
                    }
                };
                """).Returns(true);

                yield return new TestCaseData(
                    "function Test-Function { }"
                ).SetDescription("No Top Level Parameter Block").Returns(true);

                yield return new TestCaseData(
                    "param()"
                ).SetDescription("No CmdletBinding Attribute").Returns(true);

                yield return new TestCaseData("""
                [CmdletBinding()]
                param()
                """).SetDescription("CmdletBinding Attribute").Returns(false);

                yield return new TestCaseData("""
                param()

                function Test-Function {
                    [CmdletBinding()]
                    param()
                }
                """).SetDescription("No Top Level CmdletBinding Attribute, but inside function").Returns(true);

                yield return new TestCaseData("""
                function Test-Function {
                    [CmdletBinding()]
                    param()
                }
                """).SetDescription("No Top Level Param block or CmdletBinding Attribute, but inside function").Returns(true);

                yield return new TestCaseData("""
                [CmdletBinding()]
                param()

                function Test-Function {
                    [CmdletBinding()]
                    param()
                }
                """).SetDescription("Top Level CmdletBinding Attribute, and inside function").Returns(false);
            }
        }
    }
}
