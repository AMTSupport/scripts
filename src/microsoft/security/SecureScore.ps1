Using module ../../common/Environment.psm1
Using module ../Common.psm1

Using module Microsoft.Graph.Beta.Security

function Get-SecureScore(
    [System.DateTime]$Date = (Get-Date)
) {
    $Local:Score = Get-MgBetaSecuritySecureScore -Filter "CreatedDateTime eq $($Date.toString('yyyy-MM-dd'))";
    return $Local:Score;
}

function Get-SecureScoreDifference {
    $Local:ScoreToday = Get-SecureScore;
    $Local:ScoreLastMonth = Get-SecureScore -Date (Get-Date).AddMonths(-1);

if ($Local:ScoreToday -and $Local:ScoreLastMonth) {
        function Get-Percentage($Score) {
            return [Math]::Round(($Score.CurrentScore / $Score.MaxScore) * 100, 2);
        }

        $Local:Score = [PSCustomObject]@{
            Before = Get-Percentage -Score $Local:ScoreLastMonth;
            After = Get-Percentage -Score $Local:ScoreToday;
            Changes = @();
        };

        $Local:Changes = @();

        # Filter all Intune controls and minus their impact from the total score
        foreach ($Local:Control in $Local:ScoreToday.ControlScores) {
            $Local:LastMonthControl = $Local:ScoreLastMonth.ControlScores | Where-Object { $_.ControlCategory -eq $Local:Control.ControlCategory -and $_.ControlName -eq $Local:Control.ControlName };

            if ($Local:LastMonthControl) {
                $Local:Change = [PSCustomObject]@{
                    Name = $Local:Control.ControlName;
                    Increase = $Local:Control.Score - $Local:LastMonthControl.Score;
                };

                $Local:Changes += $Local:Change;
            }
        }

        foreach ($Local:Control in $Local:ScoreToday.ControlScores) {
            $Local:LastMonthControl = $Local:ScoreLastMonth.ControlScores | Where-Object { $_.ControlCategory -eq $Local:Control.ControlCategory -and $_.ControlName -eq $Local:Control.ControlName };

            if ($Local:LastMonthControl) {
                $Local:Change = [PSCustomObject]@{
                    Name = $Local:Control.ControlName;
                    Increase = $Local:Control.Score - $Local:LastMonthControl.Score;
                };

                $Local:Changes += $Local:Change;
            }
        }

        $Local:Score.Changes = $Local:Changes;

        return $Local:Score;
    }
}
