function Get-OAuth2Token {
  <#
  .SYNOPSIS
    Simplify OAuth2 token acquisition.
  .DESCRIPTION
    A longer description of the function, its purpose, common use cases, etc.
  .NOTES
    Information or caveats about the function e.g. 'This function is not supported in Linux'
  .LINK
    Specify a URI to a help page, this will show when Get-Help -Online is used.
  .EXAMPLE
    Test-MyTestFunction -Verbose
    Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [PoshRest]$Client,

    [string]$ClientId,
    [string]$ClientSecret,
    [string]$Scope = "openid profile"
  )
  # Implementation using OAuth2 flow
  $tokenRequest = [PoshRestRequest]::new("oauth/token", [HttpMethod]::Post)
  $tokenRequest.AddBody(@{
      grant_type    = "client_credentials"
      client_id     = $ClientId
      client_secret = $ClientSecret
      scope         = $Scope
    })
  $response = $Client.Execute($tokenRequest)
  return ($response.Content | ConvertFrom-Json).access_token
}