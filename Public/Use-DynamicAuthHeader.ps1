function Use-DynamicAuthHeader {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Uri,

    [Parameter(Mandatory)]
    [ScriptBlock]$TokenGenerator,

    [string]$HeaderName = "Authorization"
  )

  process {
    # Create client with dynamic auth
    $client = [PoshRest]::new($Uri.Split('/')[2..3] -join '/')
    $client.SetAuthenticator({
        param($req)
        $token = & $TokenGenerator
        $req.RequestMessage.Headers.Add($HeaderName, $token)
      }
    )

    return $client
  }
}