function Get-CachedResource {
  <#
  .SYNOPSIS
    Retrieves a resource with automatic caching support

  .DESCRIPTION
    This function uses the PoshRest SDK to fetch resources with built-in caching. It:
    - Uses the client's existing cache configuration
    - Handles query parameters and headers
    - Returns cached responses when available

  .PARAMETER Client
    PoshRest client instance (must have caching enabled)

  .PARAMETER Uri
    Resource endpoint URI

  .PARAMETER Headers
    Additional headers to send with the request

  .PARAMETER QueryParameters
    Query parameters as a hash table

  .PARAMETER AsJson
    Automatically parse JSON responses

  .EXAMPLE
    # Create client with caching
    $client = [PoshRest]::new("https://api.restful-api.dev") | EnableCache

    # First request (fetches from server)
    $result = Get-CachedResource -Client $client -Uri "/users" -QueryParameters @{page=1} -AsJson
    Write-Host "First request: $($result.count) users"

    # Second request (uses cache)
    $cachedResult = Get-CachedResource -Client $client -Uri "/users" -QueryParameters @{page=1} -AsJson
    Write-Host "Cached result: $($cachedResult.count) users"

    How it works:

    The function builds a PoshRestRequest with provided parameters
    The request is executed using the client's .Execute() method
    The SDK automatically checks the cache before making a network request
    Responses are cached for subsequent identical requests
    The function returns parsed JSON or raw content based on parameters

  .EXAMPLE
    $client = [PoshRest]::new("https://api.restful-api.dev") | EnableCache
    Get-CachedResource -Client $client -Uri "/data" -QueryParameters @{page=2}

  .EXAMPLE
    $client = [PoshRest]::new("https://api.restful-api.dev") | EnableCache
    Get-CachedResource -Client $client -Uri "/users" -Headers @{Authorization="Bearer $token"} -AsJson
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [PoshRest]$Client,

    [Parameter(Mandatory)]
    [string]$Uri,

    [hashtable]$Headers = @{},
    [hashtable]$QueryParameters = @{},
    [switch]$AsJson
  )

  # Build the request
  $request = [PoshRestRequest]::new($Uri, [HttpMethod]::Get)

  # Add headers
  foreach ($header in $Headers.GetEnumerator()) {
    $request.AddHeader($header.Name, $header.Value)
  }

  # Add query parameters
  foreach ($param in $QueryParameters.GetEnumerator()) {
    $request.AddParameter($param.Name, $param.Value, [ParameterType]::QueryString)
  }

  # Execute the request
  $response = $Client.Execute($request)

  if ($response.IsSuccessful) {
    if ($AsJson) {
      return $response.Content | ConvertFrom-Json
    } else {
      return $response.Content
    }
  } else {
    throw "HTTP Error: $($response.StatusCode) - $($response.Content)"
  }
}