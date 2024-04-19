#########################################
#
# Script to determine if the URLs required by Patch Management are accessible through .NET's HTTPWebRequest module
# Pseudocode:
# 1. Loops through each URL using an HTTPRequest
# 2. If the URL is successful, return true and otput appropriate response
# 3. If the URL is not successful, return false and output appropriate response
# 4. If the URL times out or redirects too many times, retry twice more. If on retry the request succeeds, return true. If on retries the requests fail or timeout, return false.
#
#########################################

$URLs = @(
"http://software.gfi.com/lnsupdate",
"http://lnsupdate.gfi.com/lnsupdate/index.txt",
"http://go.microsoft.com/fwlink/?LinkID=74689",
"http://download.microsoft.com",
"http://www.windowsupdate.com",
"http://update.microsoft.com",
"http://lnssupdate.gfi.com")


function GetURLStatus ($URI)
{
	try {
		$HttpWebResponse = $null;
		$HttpWebRequest = [System.Net.HttpWebRequest]::Create($URI);
		$HttpWebRequest.UseDefaultCredentials = $true
		$HttpWebRequest.PreAuthenticate = $true;
		$HttpWebRequest.CookieContainer = $CookieContainer
		$HttpWebRequest.Timeout = 10000
		$HttpWebResponse = $HttpWebRequest.GetResponse();
		if ($HttpWebResponse) {
			return $true
		}
}
catch {
  $ErrorMessage = $Error[0].Exception.ErrorRecord.Exception.Message;
  $Matched = ($ErrorMessage -match '[0-9]{3}')
  if ($Matched) {
    if ($matches[0] -eq 404)
		{
			return $false
		}
	else 
	{
		return $true
	}
  }
  else {
    $ParsedErrorMessage = $ErrorMessage -split ": "
	$ParsedErrorMessage = $ParsedErrorMessage | foreach-object { $_.Replace("`"","")}
	return $ParsedErrorMessage[1]
  }
}
}

foreach ($URL in $URLS)
{
	$Result = GetURLStatus -URI $URL
	if($Result -ne $true -and $Result -ne $false)
	{
			$Result = GetURLStatus -URI $URL
				if($Result -ne $true -and $Result -ne $false)
				{
					$Result = GetURLStatus -URI $URL
					if($Result -ne $true -and $Result -ne $false -and $Result -ne "Too many automatic redirections were attempted.")
					{
						$errorcode = 1001
					}
				}
			
	}
	write-host "URL $URL returned: $Result"
	if($Result -ne $true -and $Result -ne "Too many automatic redirections were attempted.")
	{
		$errorcode = 1001
	}
}
exit $errorcode