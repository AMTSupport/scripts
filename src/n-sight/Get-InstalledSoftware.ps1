#Requires -Version 7.0

Using module ..\common\Environment.psm1
Using module ..\common\Logging.psm1
Using module ..\common\Scope.psm1
Using module ..\common\Cache.psm1
Using module ..\common\Input.psm1

Using module ImportExcel

[CmdletBinding()]
param (
    [String]$Endpoint = 'system-monitor.com',

    [Parameter(Mandatory)]
    [ValidateLength(32, 32)]
    [String]$ApiKey,

    [ValidateSet('Workstation', 'Server')]
    [String[]]$DeviceTypes = @('Workstation', 'Server')
);

#region N-Able API Functions
function Invoke-NableApi {
    param (
        [Parameter(Mandatory)]
        [String]$Service,

        [String[]]$ExtraPath
    );

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:ParsedResponse; }

    process {
        [String]$Local:URL = "https://${Endpoint}/api/?apikey=${ApiKey}&service=$Service$(if ($ExtraPath) { "&$($ExtraPath -join '&')"})";
        [String]$Local:ContentType = 'text/xml;charset="utf-8"';
        [String]$Local:Method = 'GET';

        Invoke-Debug "Invoking N-Able API with URL: $Local:URL";

        $Local:Response = Invoke-RestMethod `
            -Uri $Local:URL `
            -Method $Local:Method `
            -ContentType $Local:ContentType;

        # TODO :: Add error handling for the response
        [System.Xml.XmlElement]$Local:ParsedResponse = $Local:Response.result;
        return $Local:ParsedResponse;
    }
}

function Get-NableClient {
    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Sites; }

    process {
        $Local:Clients = (Invoke-NableApi -Service 'list_clients' -ExtraPath 'devicetype=workstation');
        return $Local:Clients;
    }
}

function Get-NableSite {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [String[]]$ClientIds
    );

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Sites; }

    process {
        $Sites = @();

        $ClientIds | ForEach-Object {
            $Local:Site = (Invoke-NableApi -Service 'list_sites' -ExtraPath "clientid=$_").items.site;
            $Sites += $Local:Site;
        }

        return $Local:Sites;
    }
}

function Get-NableDevice {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [String[]]$SiteIds,

        [Parameter(Mandatory)]
        [ValidateSet('Workstation', 'Server')]
        [String]$DeviceType
    );

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Devices; }

    process {
        [String]$Local:CallService = "list_$($DeviceType.ToLower())s";

        $Local:Devices = @();

        $SiteIds | ForEach-Object {
            $Local:Device = (Invoke-NableApi -Service $Local:CallService -ExtraPath "siteid=$_").items.${DeviceType};
            $Devices += $Local:Device;
        }

        return $Local:Devices;
    }
}

function Get-NableDeviceoftware {
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [String[]]$DeviceIds
    );

    begin { Enter-Scope; }
    end { Exit-Scope -ReturnValue $Local:Software; }

    process {
        $Local:AllSoftware = @();

        $DeviceIds | ForEach-Object {
            $Local:Software = (Invoke-NableApi -Service 'list_all_software' -ExtraPath "assetid=$_").items.software;
            $AllSoftware += $Local:Software;
        }

        return $Local:Software;
    }
}

#endregion

function Out-ToExcel {
    param(
        [Parameter(Mandatory)]
        [String]$File,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [PSCustomObject]$Data
    );

    begin { Enter-Scope; }
    end { Exit-Scope; }

    process {
        $Local:Headers = $Data.Headers;
        $Local:Matrix = $Data.Matrix;

        #region Validate Data Structure
        # Ensure we have valid data structure in the object.
        # This should have an array called headers which defines the column names.
        # We should also have a matrix called data which is indexed by the row then by the column,
        # We should not have any rows longer than the header length.
        if (-not $Local:Headers -or -not $Local:Matrix) {
            throw 'Invalid data structure. Please ensure the object has headers and rows properties.';
        }

        if (-not $Local:Headers -is [Array] -or -not $Local:Matrix -is [System.Collections.Generic.List[System.Object]]) {
            throw 'Invalid data structure. Please ensure the headers and rows properties are arrays.';
        }
        #endregion

        #region Create Excel File
        [OfficeOpenXml.ExcelPackage]$Local:Excel = [OfficeOpenXml.ExcelPackage]::new();
        [OfficeOpenXml.ExcelWorksheet]$Local:Sheet = $Local:Excel.Workbook.Worksheets.Add('Data');
        #endregion

        #region Insert Data
        for ($i = 0; $i -lt $Local:Headers.Length; $i++) {
            Invoke-Debug "Writing header: $($Local:Headers[$i]) to cell [1, $($i + 1)]";
            $Local:Sheet.Cells[1, ($i + 1)].Value = $Local:Headers[$i];
        }

        for ($i = 0; $i -lt $Local:Matrix.Count; $i++) {
            Invoke-Debug "Row: $($i + 1) - $($Local:Matrix[$i])";

            for ($j = 0; $j -lt $Local:Headers.Length; $j++) {
                [Int]$Local:SheetRow = $i + 2;
                [Int]$Local:SheetColumn = $j + 1;

                # if ($Local:Matrix[$i].Length -le $j) {
                #     continue;
                # }

                Invoke-Debug "Writing value: $($Local:Matrix[$i][$j]) to cell [$Local:SheetRow, $Local:SheetColumn]"
                $Local:Sheet.Cells[$Local:SheetRow, $Local:SheetColumn].Value = $Local:Matrix[$i][$j];
            }
        }
        #endregion

        #region Format Excel File
        [String]$Local:LastColumn = $Local:Sheet.Dimension.Address -split ':' | Select-Object -Last 1;
        [String]$Local:LastColumn = $lastColumn -replace '[0-9]', '';

        Set-ExcelRange -Worksheet $Local:Sheet -Range "A1:$($Local:LastColumn)1" -Bold -HorizontalAlignment Center
        Set-ExcelRange -Worksheet $Local:Sheet -Range "A2:$($Local:LastColumn)$(($Local:Sheet.Dimension.Rows))" -AutoSize -ResetFont -BackgroundPattern Solid
        #endregion

        Close-ExcelPackage -ExcelPackage:$Local:Excel -SaveAs:$File -Show;

    }
}

Invoke-RunMain $PSCmdlet {
    $Local:Clients = @{ };
    $Local:RawClients = (Get-NableClient);

    [Int]$Local:PercentPerItem = 100 / $Local:RawClients.items.client.Count;
    [Int]$Local:PercentComplete = 0;

    Invoke-Debug "Processing clients: $($Local:RawClients.items.client.Count)";

    # Query user for what clients to process with a multi-select list.
    $Local:SelectedClients = (Get-PopupSelection `
            -AllowMultiple `
            -Title 'Select Clients to Process' `
            -Items ($Local:RawClients.items.client | ForEach-Object {
                [PSCustomObject]@{
                    Name             = $_.name.'#cdata-section';
                    ClientId         = $_.clientid;
                    WorkstationCount = $_.workstation_count;
                    ServerCount      = $_.server_count;
                }
            })) | Where-Object { $null -ne $_ };

    if ($null -eq $Local:SelectedClients -or $Local:SelectedClients.Count -eq 0) {
        Invoke-Error 'No clients selected to process.';
        return;
    }

    Invoke-Info "Processing $($Local:SelectedClients.Count) clients.";

    foreach ($Client in $Local:SelectedClients) {
        $ClientId = $Client.ClientId;
        Invoke-Debug "Processing client: $($Local:Client.Name) with ID: $ClientId";

        Invoke-Debug "Processing client: $($Local:Client.Name)";
        Write-Progress `
            -Activity 'Calling API' `
            -Status "$Local:PercentComplete% Complete" `
            -CurrentOperation "Processing client [$($Local:Client.name)]..." `
            -PercentComplete $Local:PercentComplete;

        if ($Local:Clients[$ClientId] -and $Local:Clients[$ClientId].completed) {
            Invoke-Debug "Client already processed: $ClientId";
            continue;
        }

        $Local:Clients[$ClientId] = @{ name = $Local:Client.Name; completed = $false; };
        $Local:Clients[$ClientId].sites = @{ };

        $Local:Sites = (Get-NableSite -ClientIds $ClientId);
        if ($Local:Sites -eq $null -or $Local:Sites.Count -eq 0) {
            Invoke-Verbose "No sites found for client: $ClientId";
            continue;
        }

        foreach ($Local:Site in $Local:Sites) {
            $SiteId = $Local:Site.siteid;
            Invoke-Debug "Processing site: $SiteId";

            if ($Local:Clients[$ClientId].sites[$SiteId] -and $Local:Clients[$ClientId].sites[$SiteId].completed) {
                Invoke-Debug "Site already processed: $SiteId";
                continue;
            }

            $Local:Clients[$ClientId].sites[$SiteId] = @{ name = $Local:Site.name.'#cdata-section'; completed = $false };

            #region Workstations
            function Set-DeviceSoftware {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                    'PSUseShouldProcessForStateChangingFunctions',
                    '',
                    Justification = 'Only reading data from the API, no changes are being made to the system.'
                )]
                param(
                    [Parameter(Mandatory)]
                    [ValidateSet('Workstation', 'Server')]
                    [String]$DeviceType,

                    [Parameter(Mandatory)]
                    [String]$SiteId,

                    [Parameter(Mandatory)]
                    [String]$ClientId,

                    [Parameter(Mandatory)]
                    [Object]$Clients
                )

                Get-CachedContent -Name "NSIGHT_${ClientId}_${SiteId}_${DeviceType}" -MaxAge (New-TimeSpan -Days 1) -CreateBlock {
                    $Clients[$ClientId].sites[$SiteId].${DeviceType} = @{ };
                    $Local:Table = $Clients[$ClientId].sites[$SiteId].${DeviceType};

                    $Local:Devices = (Get-NableDevice -SiteIds $SiteId -DeviceType $DeviceType);
                    if ($null -eq $Local:Devices -or $Local:Devices.Count -eq 0) {
                        return $Local:Table | ConvertTo-Json -Depth 9;
                    }

                    foreach ($Local:Device in $Local:Devices) {
                        $AssetId = $Local:Device.assetid;
                        Invoke-Debug "Processing ${DeviceType}: $AssetId";

                        if ($Local:Table[$AssetId] -and $Local:Table[$AssetId].completed) {
                            Invoke-Debug "${DeviceType} already processed: $AssetId";
                            return;
                        }

                        $Local:Table[$AssetId] = @{ type = $DeviceType; name = $Local:Device.name.'#cdata-section'; user = $Local:Device.user.'#cdata-section'; completed = $false };
                        $Local:Table[$AssetId].software = @{ };

                        $Local:Software = (Get-NableDeviceoftware -DeviceIds $AssetId);
                        if ($null -eq $Local:Software -or $Local:Software.Count -eq 0) {
                            return;
                        }

                        foreach ($Local:Program in $Local:Software) {
                            $SoftwareId = $Local:Program.softwareid;
                            Invoke-Debug "Processing software: $SoftwareId";

                            $Local:Table[$AssetId].software[$SoftwareId] = @{ name = $Local:Program.name.'#cdata-section'; version = $Local:Program.version.'#cdata-section'; };
                        };

                        $Local:Table[$AssetId].completed = $true;
                    };

                    return $Local:Table | ConvertTo-Json -Depth 9;
                } -ParseBlock {
                    param($RawContent)

                    $Clients[$ClientId].sites[$SiteId].${DeviceType} = ConvertFrom-Json $RawContent -AsHashtable;
                };
            }

            foreach ($DeviceType in $DeviceTypes) {
                Set-DeviceSoftware -DeviceType $DeviceType -SiteId $SiteId -ClientId $ClientId -Clients $Local:Clients;
            }

            $Local:Clients[$ClientId].sites[$SiteId].completed = $true;
        };

        $Local:Clients[$ClientId].completed = $true;
        $Local:PercentComplete += $Local:PercentPerItem;
    };
    Write-Progress -Activity 'Calling API' -PercentComplete 100 -Completed;

    $Local:Data = @{
        Headers = @('Client', 'Site', 'DeviceType', 'Device', 'User', 'Software', 'Version');
        Matrix  = New-Object 'System.Collections.Generic.List[System.Object]';
    };

    $Local:Clients.GetEnumerator() | ForEach-Object {
        $Client = $_.Value;

        $Client.sites.GetEnumerator() | ForEach-Object {
            $Site = $_.Value;

            function Add-ToMatrix {
                param(
                    [Parameter(Mandatory)]
                    $Data,

                    [Parameter(Mandatory)]
                    $Client,

                    [Parameter(Mandatory)]
                    $Site,

                    [Parameter(Mandatory)]
                    [ValidateSet('Workstation', 'Server')]
                    [String]$DeviceType
                );

                $Site.${DeviceType}.GetEnumerator() | ForEach-Object {
                    $Device = $_.Value;

                    $Device.software.GetEnumerator() | ForEach-Object {
                        $Software = $_.Value;

                        $Local:Row = New-Object 'System.Collections.Generic.List[System.Object]';
                        $Local:Row.Add($Client.name);
                        $Local:Row.Add($Site.name);
                        $Local:Row.Add($Device.type);
                        $Local:Row.Add($Device.name);
                        $Local:Row.Add($Device.user);
                        $Local:Row.Add($Software.name);
                        $Local:Row.Add($Software.version);

                        $Data.Matrix.Add($Local:Row);
                    };
                };
            }

            foreach ($DeviceType in $DeviceTypes) {
                Add-ToMatrix -Data:$Local:Data -Client $Client -Site $Site -DeviceType $DeviceType;
            }
        };
    };

    Out-ToExcel -File:($env:TEMP | Join-Path -ChildPath 'N-Sight_All-Software.xlsx') -Data:$Local:Data;

    # $Sites = Get-CachedContent -Name 'NSIGHT_SITES' -MaxAge (New-TimeSpan -Days 1) -CreateBlock {
    #     $Local:Clients = Get-NableClient;
    #     $Local:Sites = Get-NableSite -ClientIds $Clients.items.client.clientid;

    #     $Local:Sites | ConvertTo-Json;
    #     # [Newtonsoft.Json.JsonConvert]::SerializeXmlNode($Sites, 'indent')
    # } -ParseBlock {
    #     param($RawContent)

    #     # [Newtonsoft.Json.JsonConvert]::DeserializeXmlNode($_);
    #     ConvertFrom-Json $RawContent;
    # };

    # $Devices = Get-CachedContent -Name 'NSIGHT_DEVICES' -MaxAge (New-TimeSpan -Days 1) -CreateBlock {
    #     $Local:Devices = Get-NableDevice -SiteIds $Sites;

    #     $Local:Devices | ConvertTo-Json;
    #     # [Newtonsoft.Json.JsonConvert]::SerializeXmlNode($Devices, 'indent');
    # } -ParseBlock {
    #     ConvertFrom-Json $_;
    #     # [Newtonsoft.Json.JsonConvert]::DeserializeXmlNode($_);
    # };

    # $Software = Get-CachedContent -Name 'NSIGHT_SOFTWARE' -MaxAge (New-TimeSpan -Days 1) -CreateBlock {
    #     $Local:Software = Get-NableSoftware -DeviceIds $Devices.items.device.deviceid;

    #     [Newtonsoft.Json.JsonConvert]::SerializeXmlNode($Software, 'indent');
    # } -ParseBlock {
    #     [Newtonsoft.Json.JsonConvert]::DeserializeXmlNode($_);
    # };
};
