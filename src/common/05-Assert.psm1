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
            Invoke-Error -Message "Object [$Object] does not equal expected value [$Expected]";
            Invoke-FailedExit -ExitCode $Script:FAILED_EXPECTED_VALUE;
        }
        else {
            Invoke-Error -Message $Message;
            Invoke-FailedExit -ExitCode $Script:FAILED_EXPECTED_VALUE;
        }
    }
}

Export-ModuleMember -Function Assert-NotNull,Assert-Equals;
