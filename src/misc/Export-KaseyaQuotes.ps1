[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, HelpMessage = 'Where to save the output file.')]
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
            }
            else {
                $Private:UsingUri = $Local:Uri;
            }

            Invoke-Debug "Requesting Uri {{$Private:UsingUri}} with headers {{$($Local:Headers | ConvertTo-Json)}}";
            try {
                $Local:Response = Invoke-WebRequest -UseBasicParsing -Uri $Local:UsingUri -Headers $Local:Headers;
            }
            catch [Microsoft.PowerShell.Commands.HttpResponseException] {
                if ($_.Exception.Response.StatusCode -eq 429) {
                    Invoke-Info 'Rate limit reached, waiting 60 seconds before retrying...';
                    Start-Sleep -Seconds 60;
                    continue;
                }
                else {
                    Invoke-Error "There was an error with the API request. Please try again: $($_.Exception.Response.Content)";
                    break;
                }
            }
        } while ($null -eq $Local:Response -or $Local:Response.StatusCode -ne 200);

        if ($Local:Response.StatusCode -eq 200) {
            return $Local:Response.Content | ConvertFrom-Json;
        }
        else {
            Invoke-Error "There was an error with the API request. Please try again: $($_.Exception.Response.Content)";
            Invoke-FailedExit -ExitCode 9999;
        }
    }
    else {
        $Private:Responses = @();
        while ($True) {
            $Private:NextPage = "${Local:Uri}?page=$($Private:Responses.Count + 1)&pagesize=100";
            if ($null -ne $Parameters -and $Parameters.Count -gt 0) {
                $Private:NextPage += '&' + ($Parameters.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '&';
            }

            Invoke-Debug "Requesting Uri {{$Private:NextPage}} with headers {{$($Local:Headers | ConvertTo-Json)}}";
            try {
                $Private:Response = Invoke-WebRequest -UseBasicParsing -Uri $Private:NextPage -Headers $Local:Headers
            }
            catch [Microsoft.PowerShell.Commands.HttpResponseException] {
                if ($_.Exception.Response.StatusCode -eq 429) {
                    Invoke-Info 'Rate limit reached, waiting 60 seconds before retrying...';
                    Start-Sleep -Seconds 60;
                    continue;
                }
                else {
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

Import-Module $PSScriptRoot/../common/00-Environment.psm1;
Invoke-RunMain $MyInvocation {
    if ($null -ne $InputDataPath) {
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
                Set-Variable -Scope Global -Name $VariableName -Value $InputData[$VariableName];
            }
            else {
                Set-Variable -Scope Global -Name $VariableName -Value (&$LazyBlock);
            }
        }
    }

    Set-InputOrLazy -VariableName 'Quotes' -LazyBlock { Invoke-ApiRequest -Location 'quote' -PaginatedQuery };
    Set-InputOrLazy -VariableName 'QuoteLines' -LazyBlock { Invoke-ApiRequest -Location 'quoteline' -PaginatedQuery };
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
        foreach ($Local:QuoteSection in $Local:QuoteSections) {
            [String]$Local:QuoteId = $Local:QuoteSection.QuoteId;
            if (-not $Local:QuoteLines.ContainsKey($Local:QuoteId)) {
                $Local:QuoteLines[$Local:QuoteId] = Invoke-ApiRequest -Location 'quoteline' -Parameters @{ quoteId = $Local:QuoteId };
            }
        }

        $Local:QuoteLines;
    }

    if ($RawData) {
        @{
            Quotes             = $Global:Quotes;
            QuoteLines         = $Global:QuoteLines;
            SalesOrders        = $Global:SalesOrders;
            SalesOrderLines    = $Global:SalesOrderLines;
            SalesOrderPayments = $Global:SalesOrderPayments;
            Products           = $Global:Products;
            Brands             = $Global:Brands;
            Categories         = $Global:Categories;
            Customers          = $Global:Customers;
            QuoteSections      = $Global:QuoteSections;
        } | ConvertTo-Json -Depth 9 | Out-File -FilePath $OutputPath -Force;
    }
    else {
        $Global:Quotes | ForEach-Object {
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
                    $Local:Section = $_;
                    $Local:Section = $Local:Section | Select-Object -Property id, title, description;

                    $Local:Section | Add-Member -MemberType NoteProperty -Name Lines -Value ($Global:QuoteLines["$($Local:RawQuote.id)"] | Where-Object { $_.quoteSectionId -eq $Local:Section.id } | ForEach-Object {
                            $Local:Line = $_;
                            $Local:Line | Select-Object -Property id, productId, quantity, price, discount, tax, total;
                        });
                });

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
                    $Local:Quote.Sale = @{};
                }

                $Local:Quote.Sale | Add-Member -MemberType NoteProperty -Name Status -Value $Local:Status;
                $Local:Quote.Sale | Add-Member -MemberType NoteProperty -Name FulfillmentStatus -Value $Local:FulfillmentStatus;

                # $Local:Quote.Sale | Add-Member -MemberType NoteProperty -Name Lines -Value ($Global:SalesOrderLines.Values | Where-Object { $_.salesOrderID -eq $Local:RawQuote.salesOrderID } | ForEach-Object {
                #         $Local:SalesOrderLine = $_;
                #         $Local:SalesOrderLine | Select-Object -Property id, productId, quantity, price, discount, tax, total;
                #     });
                $Global:Quote = $Local:Quote
            }

            $Local:Quote;
        } | ConvertTo-Json -Depth 9 | Out-File -FilePath $OutputPath -Force;

        # Product = @{
        #     Meta     = @{
        #         Brands     = $Global:Brands.Values | ForEach-Object {
        #             $Local:Brand = $_;
        #             $Local:Brand | Select-Object -Property id, name;
        #         };

        #         Categories = $Global:Categories.Values | ForEach-Object {
        #             $Local:Category = $_;
        #             $Local:Category | Select-Object -Property id, parentID, name;
        #         };
        #     };

        #     Products = $Global:Products.Values | ForEach-Object {
        #         $Private:RawProduct = $_;
        #         $Private:Product = $Private:RawProduct | Select-Object -Property id, productNumber, manufacturerPartNumber, title, price, retailPrice;
        #         $Private:Product | Add-Member -MemberType NoteProperty -Name Brand -Value ($Global:Brands["$($Private:RawProduct.BrandId)"] | Select-Object -Property id, name);
        #         $Private:Product | Add-Member -MemberType NoteProperty -Name Category -Value ($Global:Categories["$($Private:RawProduct.CategoryId)"] | Select-Object -Property id, parentID, name);
        #         $Private:Product;
        #     };
        # }

        # Products           = $Global:Products.Values | ForEach-Object {
        #     $Local:Product = $_;
        #     $Local:Product | Select-Object -Property * #id, productNumber, manufacturerPartNumber, title, price, retailPrice;
        # };
        # }
    }
};
