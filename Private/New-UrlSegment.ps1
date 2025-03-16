function New-UrlSegment {
  param(
    [Parameter(Mandatory)]
    [string]$Template,

    [Parameter(Mandatory)]
    [hashtable]$Parameters
  )
  foreach ($param in $Parameters.GetEnumerator()) {
    $Template = $Template -replace "\{\Q$($param.Name)\Q\}", [Uri]::EscapeDataString($param.Value)
  }
  return $Template
}