param(
    [Parameter(Mandatory)]
    [string]$ModulePath,
    [Parameter(Mandatory)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$resolvedPath = (Resolve-Path $ModulePath).Path
Import-Module -Name $resolvedPath -Force

$moduleName = [System.IO.Path]::GetFileNameWithoutExtension($resolvedPath)

$commonParams = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($p in @('Verbose','Debug','ErrorAction','WarningAction','InformationAction','ErrorVariable',
                  'WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable','ProgressAction')) {
    [void]$commonParams.Add($p)
}

$result = @{}
foreach ($cmd in Get-Command -Module $moduleName) {
    if ($cmd -isnot [System.Management.Automation.CmdletInfo]) { continue }

    $typeName = $cmd.ImplementingType.FullName

    $params = [ordered]@{}
    foreach ($paramName in ($cmd.Parameters.Keys | Sort-Object)) {
        if ($commonParams.Contains($paramName)) { continue }
        $param = $cmd.Parameters[$paramName]

        $sets = [ordered]@{}
        foreach ($setName in ($param.ParameterSets.Keys | Sort-Object)) {
            $setData = $param.ParameterSets[$setName]
            $sets[$setName] = [ordered]@{
                Required = $setData.IsMandatory
                Position = if ($setData.Position -ge 0) { $setData.Position } else { $null }
                ValueFromPipeline = $setData.ValueFromPipeline
                ValueFromPipelineByPropertyName = $setData.ValueFromPipelineByPropertyName
            }
        }

        $params[$paramName] = [ordered]@{
            Type = $param.ParameterType.Name
            FullType = $param.ParameterType.FullName
            Aliases = @($param.Aliases)
            Sets = $sets
        }
    }

    $outputTypes = @()
    foreach ($ot in $cmd.OutputType) {
        if ($ot.Type) { $outputTypes += $ot.Type.FullName }
        elseif ($ot.Name) { $outputTypes += $ot.Name }
    }

    $result[$cmd.Name] = [ordered]@{
        TypeName = $typeName
        Verb = $cmd.Verb
        Noun = $cmd.Noun
        Parameters = $params
        OutputTypes = $outputTypes
    }
}

$result | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
Write-Output "Dumped metadata for $($result.Count) commands to: $OutputPath"
