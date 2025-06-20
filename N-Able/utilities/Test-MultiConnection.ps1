Param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Adresses
)

while ($true) {
    $start = Get-Date
    $Adresses | ForEach-Object {
        $result = [ordered]@{
            DNSName   = $_.Trim()
            Up        = ''
            Timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
        try {
            [array]$x = Test-Connection $result.DNSName -Delay 15 -Count 1 -ErrorAction SilentlyContinue
            if ($x) {
                $Output = "$($result.Timestamp): Reply from $($result.DNSName) time=$($x[0].ResponseTime)ms"
            } else {
                $Output = "$($result.Timestamp): Reply from $($result.DNSName) timed out."
            }
        } catch {
            $result.Up = 'Unknown'
        }

        $LogFilePath = "$env:TEMP\ping_tester.log"
        if ((Test-Path -Path $LogFilePath) -eq $false) {
            New-Item -Path $LogFilePath -ItemType File
        }

        $Output | Out-File -FilePath $LogFilePath -Append

        $Output
    }

    $duration = New-TimeSpan -Start $start -End (Get-Date)
    if ($duration.Milliseconds -lt 1000) {
        $sleep = 1000 - $duration.Milliseconds
        Write-Verbose "Sleeping for $sleep milliseconds"
        Start-Sleep -Milliseconds $sleep
    }
}
