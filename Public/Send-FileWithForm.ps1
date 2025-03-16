function Send-FileWithForm {
  [CmdletBinding()][Alias('Upload-FileWithForm')]
  param(
    [Parameter(Mandatory)]
    [string]$Uri,

    [Parameter(Mandatory)]
    [string]$FilePath,

    [hashtable]$FormFields = @{},
    [string]$FileParameterName = "file"
  )

  process {
    # Create client
    $client = [PoshRest]::new($Uri.Split('/')[2..3] -join '/')

    # Build request
    $resource = $Uri.Split('/')[-1]
    $request = [PoshRestRequest]::new($resource, [System.Net.Http.HttpMethod]::Post)
    $request.AddFile($FileParameterName, $FilePath)

    # Add form fields
    foreach ($field in $FormFields.GetEnumerator()) {
      $request.AddParameter($field.Name, $field.Value, [ParameterType]::Body)
    }

    # Execute upload
    $response = $client.Execute($request)
    if ($response.IsSuccessful) {
      Write-Host "Upload successful: $($response.StatusCode)"
    } else {
      Write-Error "Upload failed: $($response.Content)"
    }
  }
}