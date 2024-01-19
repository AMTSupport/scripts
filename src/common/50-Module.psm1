function Import-DownloadableModule {
    Param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$Name
    )

    $Local:Module = Get-Module -ListAvailable | Where-Object { $_.Name -eq $Name } | Select-Object -First 1;
    if ($Local:Module) {
        Invoke-Verbose -Message "Importing previously installed module $Name...";
        Import-Module $Local:Module;
        return;
    }

    Invoke-Verbose "Ensuring NuGet is installed..."
    Install-PackageProvider -Name NuGet -Confirm:$false;

    Invoke-Verbose "Installing module $Name...";
    Install-Module -Name $Name -Scope CurrentUser -Confirm:$false -Force;

    Invoke-Verbose "Importing module $Name...";
    Import-Module -Name $Name;
}

Export-ModuleMember -Function Import-DownloadableModule;
