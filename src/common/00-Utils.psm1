<#
.DESCRIPTION
    This module contains utility functions that have no dependencies on other modules and can be used by any module.
#>

<#
.DESCRIPTION
    This function is used to measure the time it takes to execute a script block.

.EXAMPLE
    Measure-ElapsedTime {
        Start-Sleep -Seconds 5;
    }
#>
function Measure-ElaspedTime {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ScriptBlock]$ScriptBlock
    )

    process {
        [DateTime]$Local:StartAt = Get-Date;

        & $ScriptBlock;

        [TimeSpan]$Local:ElapsedTime = (Get-Date) - $Local:StartAt;
        return $Local:ElapsedTime * 10000; # Why does this make it more accurate?
    }
}
