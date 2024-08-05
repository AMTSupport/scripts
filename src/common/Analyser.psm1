Using module ./Utils.psm1

class SupressAnalyserAttribute : System.Attribute {
    [String]$CheckType;
    [Object]$Data;
    [String]$Justification = '';

    SuppressAnalyser([String]$CheckType, [Object]$Data) {
        $this.CheckType = $CheckType;
        $this.Data = $Data;
    }

    SuppressAnalyser([String]$CheckType, [Object]$Data, [String]$Justification) {
        $this.CheckType = $CheckType;
        $this.Data = $Data;
        $this.Justification = $Justification;
    }
}

Export-Types -Types @(
    [SupressAnalyserAttribute]
)
