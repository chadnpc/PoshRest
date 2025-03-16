function Get-Cookie {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [PoshRest]$Client,

    [string]$Name
  )
  return $Client.Handler.CookieContainer.GetCookies($Client.BaseUrl).Cast[Cookie]() | Where-Object { $_.Name -eq $Name }
}

