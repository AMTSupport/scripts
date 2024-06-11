[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, HelpMessage = 'Where to save the output file.')]
    [Alias('PSPath')]
    [ValidateNotNullOrEmpty()]
    [String]$OutputPath
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
    if ($null -eq $Global:Quotes) {
        $Global:Quotes = Invoke-ApiRequest -Location 'quote' -PaginatedQuery;
    }

    if ($null -eq $Global:QuoteLines) {
        $Global:QuoteLines = Invoke-ApiRequest -Location 'quoteline' -PaginatedQuery;
    }

    if ($null -eq $Global:SalesOrders) {
        $Global:SalesOrders = Invoke-ApiRequest -Location 'salesorder' -PaginatedQuery;
    }

    if ($null -eq $Global:SalesOrderLines) {
        $Global:SalesOrderLines = Invoke-ApiRequest -Location 'salesorderline' -PaginatedQuery;
    }

    if ($null -eq $Global:SalesOrderPayments) {
        $Global:SalesOrderPayments = Invoke-ApiRequest -Location 'salesorderpayment' -PaginatedQuery;
    }

    if ($null -eq $Global:Products) {
        $Global:Products = @{};
    }

    foreach ($Local:SalesOrderLine in $Global:SalesOrderLines) {
        [String]$Local:ProductId = $Local:SalesOrderLine.ProductId;
        if (-not $Global:Products.ContainsKey($Local:ProductId)) {
            $Global:Products[$Local:ProductId] = Invoke-ApiRequest -Location "product/$Local:ProductId";
        }
    }

    if ($null -eq $Global:Brands) {
        $Global:Brands = @{};
    }

    foreach ($Local:Product in $Global:Products.Values) {
        [String]$Local:BrandId = $Local:Product.BrandId;
        if (-not $Global:Brands.ContainsKey($Local:BrandId)) {
            $Global:Brands[$Local:BrandId] = Invoke-ApiRequest -Location "brand/$Local:BrandId";
        }
    }

    if ($null -eq $Global:Categories) {
        $Global:Categories = @{};
    }

    foreach ($Local:Product in $Global:Products.Values) {
        [String]$Local:CategoryId = $Local:Product.CategoryId;
        if (-not $Global:Categories.ContainsKey($Local:CategoryId)) {
            $Global:Categories[$Local:CategoryId] = Invoke-ApiRequest -Location "category/$Local:CategoryId";
        }
    }

    if ($null -eq $Global:Customers) {
        $Global:Customers = @{};
    }


    if ($null -eq $Global:QuoteSections) {
        $Global:QuoteSections = @{};
    }

    if ($null -eq $Global:QuoteLines) {
        $Global:QuoteLines = @{};
    }

    foreach ($Local:Quote in $Global:Quotes) {
        [String]$Local:CustomerId = $Local:Quote.customerId;
        if (-not $Global:Customers.ContainsKey($Local:CustomerId)) {
            $Global:Customers[$Local:CustomerId] = Invoke-ApiRequest -Location "customer/$Local:CustomerId";
        }

        [String]$Local:QuoteId = $Local:Quote.id;
        if (-not $Global:QuoteSections.ContainsKey($Local:QuoteId)) {
            $Global:QuoteSections[$Local:QuoteId] = Invoke-ApiRequest -Location 'quotesection' -Parameters @{ quoteId = $Local:QuoteId };
        }
    }

    foreach ($Local:QuoteSection in $Global:QuoteSections) {
        [String]$Local:QuoteId = $Local:QuoteSection.QuoteId;
        if (-not $Global:QuoteLines.ContainsKey($Local:QuoteId)) {
            $Global:QuoteLines[$Local:QuoteId] = Invoke-ApiRequest -Location 'quoteline' -Parameters @{ quoteId = $Local:QuoteId };
        }
    }

    @{
        Quotes = $Global:Quotes | ForEach-Object {
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
        };

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
    } | ConvertTo-Json -Depth 9 | Out-File -FilePath $OutputPath -Force;
};
