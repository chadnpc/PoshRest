function Invoke-RestWithRetry {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Uri,

    [Parameter(Mandatory)]
    [string]$Method,

    [object]$Body,

    [hashtable]$Headers = @{},

    [int]$MaxRetries = 3,

    [timespan]$Delay = '00:00:01'
  )

  process {
    # Create PoshRest client with retry policy
    $client = [PoshRest]::new($Uri.Split('/')[2..3] -join '/')
    $client.ConfigureRetry($MaxRetries, $Delay)

    # Build request
    $request = [PoshRestRequest]::new($Uri.Split('/')[-1], [System.Net.Http.HttpMethod]::$Method)
    foreach ($header in $Headers.GetEnumerator()) {
      $request.AddHeader($header.Name, $header.Value)
    }
    if ($Body) {
      $request.AddJsonBody($Body)
    }

    # Execute with retry
    $response = $client.Execute($request)
    if (-not $response.IsSuccessful) {
      throw "Request failed after retries: $($response.StatusCode)"
    }
    return $response.Content | ConvertFrom-Json
  }
}