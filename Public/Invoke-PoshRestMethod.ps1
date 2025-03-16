function Invoke-PoshRestMethod {
  <#
  .SYNOPSIS
     Unified method for all HTTP verbs with automatic JSON parsing.
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

    [Parameter(Mandatory)]
    [string]$Uri,

    [Parameter(Mandatory)]
    [string]$Method,

    [object]$Body,

    [hashtable]$Headers = @{},

    [hashtable]$QueryParameters = @{},

    [switch]$AsJson
  )
  $request = [PoshRestRequest]::new($Uri, [HttpMethod]::$Method)
  foreach ($header in $Headers.GetEnumerator()) {
    $request.AddHeader($header.Name, $header.Value)
  }
  foreach ($param in $QueryParameters.GetEnumerator()) {
    $request.AddParameter($param.Name, $param.Value, [ParameterType]::QueryString)
  }
  if ($Body) { $request.AddJsonBody($Body) }
  $response = $Client.Execute($request)
  return $response | ConvertFrom-Json
}