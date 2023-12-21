#Requires -Version 5.1

function Assert-NotNull(
    [Parameter(Mandatory, ValueFromPipeline)]
    [Object]$Object,

    [Parameter()]
    [String]$Message
) {
    if ($null -eq $Object -or $Object -eq '') {
        if ($null -eq $Message) {
            Invoke-Error -Message 'Object is null';
            Invoke-FailedExit -ExitCode $Script:NULL_ARGUMENT;
        } else {
            Invoke-Error $Message;
            Invoke-FailedExit -ExitCode $Script:NULL_ARGUMENT;
        }
    }
}

function Assert-Equals([Parameter(Mandatory, ValueFromPipeline)][Object]$Object, [Parameter(Mandatory)][Object]$Expected, [String]$Message) {
    if ($Object -ne $Expected) {
        if ($null -eq $Message) {
            Write-Host -ForegroundColor Red -Object "Object [$Object] does not equal expected value [$Expected]";
            Invoke-FailedExit -ExitCode $Script:FAILED_EXPECTED_VALUE;
        }
        else {
            Write-Host -ForegroundColor Red -Object $Message;
            Invoke-FailedExit -ExitCode $Script:FAILED_EXPECTED_VALUE;
        }
    }
}

Export-ModuleMember -Function Assert-NotNull,Assert-Equals;
