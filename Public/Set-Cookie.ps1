function Set-Cookie {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [PoshRest]$Client,

    [string]$Name,
    [string]$Value,
    [string]$Domain = $Client.BaseUrl.Host,
    [string]$Path = "/"
  )
  $Client.AddCookie($Name, $Value, $Domain, $Path)
}