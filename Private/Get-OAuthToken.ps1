function Get-OAuthToken {
  <#
  .LINK
    Specify a URI to a help page, this will show when Get-Help -Online is used.
  .EXAMPLE
    # Create client with dynamic auth
    $client = Use-DynamicAuthHeader -Uri "https://api.example.com" -TokenGenerator ${function:Get-OAuthToken}

    # Make authenticated request
    $request = [PoshRestRequest]::new("users", [HttpMethod]::Get)
    $client.Execute($request)
  #>
  process {
    return "Bearer $(New-Guid)"
  }
}