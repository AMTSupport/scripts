function Get-ShouldBeString([String]$String) {
    $FixedString = InModuleScope Logging -ArgumentList @($String) {
        param($String)

        $NewlineReplacement = "`n+ ";
        $Prefix = '';
        if (Test-SupportsUnicode) {
            # There is an extra space at the end of the string
            $Prefix = ' ';
            $NewlineReplacement = "`n  + ";
        }

        $String = $String -replace "`n", $NewlineReplacement;
        return "$Prefix$String";
    }

    return $FixedString;
}

function Get-Stripped([Parameter(ValueFromPipeline)][String]$String) {
    # Replace all non-ASCII characters with a nothing string
    # Replace all ANSI escape sequences with a nothing string
    $String -replace '[^\u0000-\u007F]', '' -replace '\x1B\[[0-9;]*m', '';
}

Export-ModuleMember -Function Get-ShouldBeString, Get-Stripped
