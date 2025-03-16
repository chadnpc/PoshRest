function Set-Proxy {
  param(
    [Parameter(Mandatory)]
    [PoshRest]$Client,

    [string]$ProxyUrl,
    [switch]$UseDefaultCredentials
  )
  $Client.ClientHandler.UseProxy = $true
  $Client.ClientHandler.Proxy = New-Object System.Net.WebProxy($ProxyUrl)
  $Client.ClientHandler.UseDefaultCredentials = $UseDefaultCredentials
}