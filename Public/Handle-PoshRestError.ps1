function Handle-PoshRestError {
  param(
    [Parameter(Mandatory)]
    [PoshRestResponse]$Response
  )
  if (-not $Response.IsSuccessful) {
    throw "HTTP Error: $($Response.StatusCode) - $($Response.Content)"
  }
}