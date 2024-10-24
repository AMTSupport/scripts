Using module ../common/Environment.psm1
Using module ../common/Input.psm1
Using module ../common/Logging.psm1
Using module ../common/Exit.psm1
Using module ../common/Utils.psm1

[CmdletBinding()]
param(
    [Parameter(Mandatory, HelpMessage = 'Where to save the output file.')]
    [Alias('PSPath')]
    [ValidateNotNullOrEmpty()]
    [String]$OutputPath,

    [String]$InputDataPath,

    [Switch]$RawData
)

function Invoke-ApiRequest {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Location,

        [Parameter()]
        [HashTable]$Parameters,

        [Switch]$PaginatedQuery
    )

    $Local:Uri = "https://api.kaseyaquotemanager.com/v1/$Location";
    $Local:Headers = @{
        apiKey = Get-VarOrSave -VariableName 'KaseyaApiKey' -LazyValue {
            Get-UserInput 'Kaseya API Key' 'Please enter your Kaseya API Key:';
        }
    }

    if (-not $PaginatedQuery) {
        do {
            if ($null -ne $Parameters -and $Parameters.Count -gt 0) {
                $Private:UsingUri = $Local:Uri + '?' + ($Parameters.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '&';
            } else {
                $Private:UsingUri = $Local:Uri;
            }

            Invoke-Debug "Requesting Uri {{$Private:UsingUri}} with headers {{$($Local:Headers | ConvertTo-Json)}}";
            try {
                $Local:Response = Invoke-WebRequest -UseBasicParsing -Uri $Local:UsingUri -Headers $Local:Headers;
            } catch [Microsoft.PowerShell.Commands.HttpResponseException] {
                if ($_.Exception.Response.StatusCode -eq 429) {
                    Invoke-Info 'Rate limit reached, waiting 60 seconds before retrying...';
                    Start-Sleep -Seconds 60;
                    continue;
                } else {
                    Invoke-Error "There was an error with the API request. Please try again: $($_.Exception.Response.Content)";
                    break;
                }
            }
        } while ($null -eq $Local:Response -or $Local:Response.StatusCode -ne 200);

        if ($Local:Response.StatusCode -eq 200) {
            return $Local:Response.Content | ConvertFrom-Json;
        } else {
            Invoke-Error "There was an error with the API request. Please try again: $($_.Exception.Response.Content)";
            Invoke-FailedExit -ExitCode 9999;
        }
    } else {
        $Private:Responses = @();
        while ($True) {
            $Private:NextPage = "${Local:Uri}?page=$($Private:Responses.Count + 1)&pagesize=100";
            if ($null -ne $Parameters -and $Parameters.Count -gt 0) {
                $Private:NextPage += '&' + ($Parameters.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '&';
            }

            Invoke-Debug "Requesting Uri {{$Private:NextPage}} with headers {{$($Local:Headers | ConvertTo-Json)}}";
            try {
                $Private:Response = Invoke-WebRequest -UseBasicParsing -Uri $Private:NextPage -Headers $Local:Headers
            } catch [Microsoft.PowerShell.Commands.HttpResponseException] {
                if ($_.Exception.Response.StatusCode -eq 429) {
                    Invoke-Info 'Rate limit reached, waiting 60 seconds before retrying...';
                    Start-Sleep -Seconds 60;
                    continue;
                } else {
                    Invoke-Error "There was an error with the API request. Please try again: $($_.Exception.Response.Content)";
                    Invoke-FailedExit -ExitCode 9999 -ErrorRecord $_;
                }
            }

            if ($Private:Response.StatusCode -eq 200) {
                if ($Private:Response.Content -eq '[]') {
                    Invoke-Info 'No more data to retrieve, breaking loop.';
                    break;
                }

                $Private:Responses += $Private:Response;
            }
        }

        $Private:Content = @();
        foreach ($Private:Response in $Private:Responses) {
            $Private:Content += ($Private:Response.Content | ConvertFrom-Json);
        }

        return $Private:Content;
    }
}

Invoke-RunMain $PSCmdlet {
    trap {
        Remove-Variable -Scope Global -Name 'Quotes' -ErrorAction SilentlyContinue;
        Remove-Variable -Scope Global -Name 'QuoteSections' -ErrorAction SilentlyContinue;
        Remove-Variable -Scope Global -Name 'QuoteLines' -ErrorAction SilentlyContinue;
        Remove-Variable -Scope Global -Name 'SalesOrders' -ErrorAction SilentlyContinue;
        Remove-Variable -Scope Global -Name 'SalesOrderLines' -ErrorAction SilentlyContinue;
        Remove-Variable -Scope Global -Name 'SalesOrderPayments' -ErrorAction SilentlyContinue;
        Remove-Variable -Scope Global -Name 'Products' -ErrorAction SilentlyContinue;
        Remove-Variable -Scope Global -Name 'Brands' -ErrorAction SilentlyContinue;
        Remove-Variable -Scope Global -Name 'Categories' -ErrorAction SilentlyContinue;
        Remove-Variable -Scope Global -Name 'Customers' -ErrorAction SilentlyContinue;
    };

    if (-not [string]::IsNullOrWhiteSpace($InputDataPath)) {
        Invoke-Debug "Reading input data from $InputDataPath";
        $Local:RawContent = Get-Content -Path $InputDataPath;
        if ($null -eq $Local:RawContent) {
            Invoke-Error "The input data file at '$InputDataPath' could not be found.";
            Invoke-FailedExit -ExitCode 9999;
        }

        $InputData = $Local:RawContent | ConvertFrom-Json -AsHashtable;
    }

    function Set-InputOrLazy([String]$VariableName, [ScriptBlock]$LazyBlock) {
        if ($null -eq (Get-Variable -Scope Global -Name $VariableName -ValueOnly -ErrorAction SilentlyContinue)) {
            if ($null -ne $InputData -and $InputData.ContainsKey($VariableName)) {
                Invoke-Debug "Setting variable $VariableName from input data.";
                Set-Variable -Scope Global -Name $VariableName -Value $InputData[$VariableName];
            } else {
                Invoke-Debug "Setting variable $VariableName from lazy block.";
                Set-Variable -Scope Global -Name $VariableName -Value (&$LazyBlock);
            }
        }
    }

    Set-InputOrLazy -VariableName 'Quotes' -LazyBlock { Invoke-ApiRequest -Location 'quote' -PaginatedQuery };

    Set-InputOrLazy -VariableName 'SalesOrders' -LazyBlock { Invoke-ApiRequest -Location 'salesorder' -PaginatedQuery };
    Set-InputOrLazy -VariableName 'SalesOrderLines' -LazyBlock { Invoke-ApiRequest -Location 'salesorderline' -PaginatedQuery };
    Set-InputOrLazy -VariableName 'SalesOrderPayments' -LazyBlock { Invoke-ApiRequest -Location 'salesorderpayment' -PaginatedQuery };

    Set-InputOrLazy -VariableName 'Products' -LazyBlock {
        $Local:Products = @{};
        foreach ($Local:SalesOrderLine in $Global:SalesOrderLines) {
            [String]$Local:ProductId = $Local:SalesOrderLine.ProductId;
            if (-not $Local:Products.ContainsKey($Local:ProductId)) {
                $Local:Products[$Local:ProductId] = Invoke-ApiRequest -Location "product/$Local:ProductId";
            }
        }

        $Local:Products;
    };

    Set-InputOrLazy -VariableName 'Brands' -LazyBlock {
        $Local:Brands = @{};
        foreach ($Local:Product in $Global:Products.Values) {
            [String]$Local:BrandId = $Local:Product.BrandId;
            if (-not $Local:Brands.ContainsKey($Local:BrandId)) {
                $Local:Brands[$Local:BrandId] = Invoke-ApiRequest -Location "brand/$Local:BrandId";
            }
        }

        $Local:Brands;
    };

    Set-InputOrLazy -VariableName 'Categories' -LazyBlock {
        $Local:Categories = @{};
        foreach ($Local:Product in $Global:Products.Values) {
            [String]$Local:CategoryId = $Local:Product.CategoryId;
            if (-not $Local:Categories.ContainsKey($Local:CategoryId)) {
                $Local:Categories[$Local:CategoryId] = Invoke-ApiRequest -Location "category/$Local:CategoryId";
            }
        }

        $Local:Categories;
    };

    Set-InputOrLazy -VariableName 'Customers' -LazyBlock {
        $Local:Customers = @{};
        foreach ($Local:Quote in $Global:Quotes) {
            [String]$Local:CustomerId = $Local:Quote.customerId;
            if (-not $Local:Customers.ContainsKey($Local:CustomerId)) {
                $Local:Customers[$Local:CustomerId] = Invoke-ApiRequest -Location "customer/$Local:CustomerId";
            }
        }

        $Local:Customers;
    };

    Set-InputOrLazy -VariableName 'QuoteSections' -LazyBlock {
        $Local:QuoteSections = @{};
        foreach ($Local:Quote in $Global:Quotes) {
            [String]$Local:QuoteId = $Local:Quote.id;
            if (-not $Local:QuoteSections.ContainsKey($Local:QuoteId)) {
                $Local:QuoteSections[$Local:QuoteId] = Invoke-ApiRequest -Location 'quotesection' -Parameters @{ quoteId = $Local:QuoteId };
            }
        }

        $Local:QuoteSections;
    };

    Set-InputOrLazy -VariableName 'QuoteLines' -LazyBlock {
        $Local:QuoteLines = @{};
        foreach ($Local:QuoteSections in $Global:QuoteSections.Values) {
            foreach ($Local:QuoteSection in $Local:QuoteSections) {
                [String]$Local:QuoteSectionId = $Local:QuoteSection.id;
                if (-not $Local:QuoteLines.ContainsKey($Local:QuoteSectionId)) {
                    $Local:QuoteLines[$Local:QuoteSectionId] = Invoke-ApiRequest -Location 'quoteline' -Parameters @{ quoteSectionId = $Local:QuoteSectionId } -PaginatedQuery;
                }
            }
        }

        $Local:QuoteLines;
    }

    if ($RawData) {
        @{
            Quotes             = $Global:Quotes;
            QuoteSections      = $Global:QuoteSections;
            QuoteLines         = $Global:QuoteLines;
            SalesOrders        = $Global:SalesOrders;
            SalesOrderLines    = $Global:SalesOrderLines;
            SalesOrderPayments = $Global:SalesOrderPayments;
            Products           = $Global:Products;
            Brands             = $Global:Brands;
            Categories         = $Global:Categories;
            Customers          = $Global:Customers;
        } | ConvertTo-Json -Depth 9 | Out-File -FilePath $OutputPath -Force;
    } else {
        $Global:Quotes | ForEach-Object {
            Invoke-Debug "Processing quote $($_.id)";

            $Local:RawQuote = $_;
            $Local:Quote = $Local:RawQuote | Select-Object -Property id, salesOrderId, quoteNumber, title, expiryDate, createdDate, modifiedDate, privateNote;

            $Local:Status = switch ($Local:RawQuote.status) {
                '0' { 'Draft' }
                '1' { 'Sent' }
                '2' { 'Viewed' }
                '3' { 'Won' }
                '90' { 'Declined' }
            };

            $Local:Quote | Add-Member -MemberType NoteProperty -Name Status -Value $Local:Status

            $Local:Quote | Add-Member -MemberType NoteProperty -Name Customer -Value @{
                name    = $Global:Customers["$($Local:RawQuote.customerId)"].name;
                contact = $Local:RawQuote.contactName;
            };

            $Local:Quote | Add-Member -MemberType NoteProperty -Name Sections -Value ($Global:QuoteSections["$($Local:RawQuote.id)"] | ForEach-Object {
                    Invoke-Debug "Processing quote section $($_.id)";

                    $Local:Section = $_;
                    $Local:Section = $Local:Section | Select-Object -Property id, title, description;

                    $Local:Section | Add-Member -MemberType NoteProperty -Name Lines -Value ($Global:QuoteLines["$($Local:Section.id)"] | ForEach-Object {
                            if ($null -eq $_) {
                                return @{};
                            }

                            Invoke-Debug "Processing quote line $($_.id)";

                            $Local:Line = $_;
                            $Local:Line | Select-Object -Property id, productId, quantity, price, discount, tax, total;

                            $Local:Line | Add-Member -MemberType NoteProperty -Name Product -Value ($Global:Products["$($Local:Line.productID)"] | Select-Object -Property id, productNumber, manufacturerPartNumber, title);
                            $Local:Line;
                        });

                    $Local:Section;
                } | Where-Object { $null -ne $_.Lines -and $_.Lines.Count -gt 0 });

            if ($Local:Status -eq 'Won') {
                $Local:SalesOrder = $Global:SalesOrders["$($Local:RawQuote.salesOrderId)"];
                $Local:Status = switch ($Local:SalesOrder.status) {
                    '1' { 'Draft' }
                    '2' { 'Approved' }
                    '3' { 'Processed' }
                    '90' { 'Cancelled' }
                    default { 'Unknown' }
                };
                $Local:FulfillmentStatus = switch ($Local:SalesOrder.fulfillmentStatus) {
                    '0' { 'None' }
                    '1' { 'Fulfilled' }
                    '2' { 'Partial' }
                    default { 'Unknown' }
                };

                # FIXME Some are null?
                $Local:Quote | Add-Member -MemberType NoteProperty -Name Sale -Value ($Local:SalesOrder | Select-Object -Property orderNumber, notes, orderDate, createdDate, modifiedDate);
                if ($null -eq $Local:Quote.Sale) {
                    Invoke-Warn "No sales order found for quote $($Local:RawQuote.id), creating empty sale object.";
                    $Local:Quote.Sale = @{};
                }

                $Local:Quote.Sale | Add-Member -MemberType NoteProperty -Name Status -Value $Local:Status;
                $Local:Quote.Sale | Add-Member -MemberType NoteProperty -Name FulfillmentStatus -Value $Local:FulfillmentStatus;
                $Local:Quote.Sale | Add-Member -MemberType NoteProperty -Name Lines -Value ($Global:SalesOrderLines | Where-Object { $_.salesOrderID -eq $Local:RawQuote.salesOrderID } | ForEach-Object {
                        Invoke-Debug "Processing sales order line $($_.id)";

                        $Local:SalesOrderLine = $_;
                        $Local:SalesOrderLine | Select-Object -Property id, productId, quantity, price, discount, tax, total;
                    });
            }

            $Local:Quote;
        } | ConvertTo-Json -Depth 9 | Out-File -FilePath $OutputPath -Force;

        Invoke-Info "Exported quotes to $OutputPath";
    }
};
