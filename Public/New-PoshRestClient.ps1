function New-PoshRestClient {
  <#
  .SYNOPSIS
    Simplify client creation with defaults.
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
    [string]$BaseUri,

    [hashtable]$DefaultHeaders = @{},
    [hashtable]$DefaultParameters = @{},
    [switch]$EnableCaching
  )
  $client = [PoshRest]::new($BaseUri)
  foreach ($header in $DefaultHeaders.GetEnumerator()) {
    $client.AddDefaultHeader($header.Name, $header.Value)
  }
  foreach ($param in $DefaultParameters.GetEnumerator()) {
    $client.AddDefaultParameter($param.Name, $param.Value, [ParameterType]::QueryString)
  }
  if ($EnableCaching) { $client.EnableCache() }
  return $client
}