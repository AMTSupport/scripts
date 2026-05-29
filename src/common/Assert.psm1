#Requires -Version 5.1

Using module ..\..\Output\PowerShellModules\AMT.PowerShell.Common\AMT.PowerShell.Common.psd1
Using module .\Logging.psm1
Using module .\Exit.psm1

$NULL_ARGUMENT = Register-ExitCode -Description 'An unexpected null value was encountered.';
$FAILED_EXPECTED_VALUE = Register-ExitCode -Description 'Object [{0}] does not equal expected value [{1}].';

function Assert-NotNull(
    [Parameter(ValueFromPipeline)]
    [Object]$Object,

    [Parameter()]
    [AllowNull()]
    [String]$Message
) {
    if ([AMT.PowerShell.Common.Assertions.AssertionHelper]::IsNotNull($Object)) {
        return;
    }

    if (-not [String]::IsNullOrWhiteSpace($Message)) { Invoke-Error -Message $Message; }
    Invoke-FailedExit -ExitCode $NULL_ARGUMENT;
}

function Assert-Equal(
    [Parameter(Mandatory, ValueFromPipeline)]
    [Object]$Object,

    [Parameter(Mandatory)]
    [Object]$Expected,

    [Parameter()]
    [String]$Message
) {
    if ([AMT.PowerShell.Common.Assertions.AssertionHelper]::AreEqual($Object, $Expected)) { return }

    if (-not [String]::IsNullOrWhiteSpace($Message)) { Invoke-Error -Message $Message; }
    Invoke-FailedExit -ExitCode $FAILED_EXPECTED_VALUE -FormatArgs @($Object, $Expected);
}

Export-ModuleMember -Function Assert-NotNull, Assert-Equal;
