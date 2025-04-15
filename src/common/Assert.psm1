#Requires -Version 5.1

Using module .\Logging.psm1
Using module .\Exit.psm1

$NULL_ARGUMENT = Register-ExitCode -Description 'An unexpected null value was encountered.';
$FAILED_EXPECTED_VALUE = Register-ExitCode -Description 'Object [{0}] does not equal expected value [{1}].';


<#
.SYNOPSIS
    Asserts that the given value is not null.

.DESCRIPTION
    The Assert-NotNull function checks if the provided value is not null.
    If the value is null, it throws an exception.

.PARAMETER Object
    The value to be checked for null.

.EXAMPLE
    This will result in nothing happening as the value is not null.
    ```powershell
    Assert-NotNull -Object 'foo';
    ```

.EXAMPLE
    This will result in an error being thrown as the value is null.
    ```powershell
    Assert-NotNull -Object $null;
    ```
#>
function Assert-NotNull(
    [Parameter(ValueFromPipeline)]
    [Object]$Object,

    [Parameter()]
    [AllowNull()]
    [String]$Message
) {
    if ($null -ne $Object) {
        return;
    }

    if (-not [String]::IsNullOrWhiteSpace($Message)) { Invoke-Error -Message $Message; }
    Invoke-FailedExit -ExitCode $NULL_ARGUMENT;
}

<#
.SYNOPSIS
    Asserts that two values are equal.

.DESCRIPTION
    The Assert-Equal function compares two values and throws an error if they are not equal.

.PARAMETER Object
    The object you want to test against the expected value.

.PARAMETER Expected
    The expected value.

.EXAMPLE
    This will pass as the expected value is equal to the actual value.
    ```powershell
    Assert-Equal -Expected 5 -Actual 5
    ```

.EXAMPLE
    This will throw an error as the expected value is not equal to the actual value.
    ```powershell
    Assert-Equal -Expected 5 -Actual 3
    ```
#>
function Assert-Equal(
    [Parameter(Mandatory, ValueFromPipeline)]
    [Object]$Object,

    [Parameter(Mandatory)]
    [Object]$Expected,

    [Parameter()]
    [String]$Message
) {
    if ($Object -eq $Expected) { return }

    if (-not [String]::IsNullOrWhiteSpace($Message)) { Invoke-Error -Message $Message; }
    Invoke-FailedExit -ExitCode $FAILED_EXPECTED_VALUE -FormatArgs @($Object, $Expected);
}

Export-ModuleMember -Function Assert-NotNull, Assert-Equal;
