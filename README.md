# PoshRest

[![Build Status](https://github.com/chadnpc/PoshRest/actions/workflows/build_module.yaml/badge.svg)](https://github.com/chadnpc/PoshRest/actions) [![PowerShell Gallery](https://img.shields.io/powershellgallery/v/PoshRest.svg)](https://www.powershellgallery.com/packages/PoshRest) [![Downloads](https://img.shields.io/powershellgallery/dt/PoshRest.svg)](https://www.powershellgallery.com/packages/PoshRest)

A lightweight PowerShell module for working with HTTP RESTful APIs.

If you want advanced features beyond basic [`Invoke-RestMethod`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-restmethod) while maintaining PowerShell syntax, then this module is for you.

Stuff like:

- **Caching**: GET request caching
- **Serialization**: JSON/XML with custom options
- **Retry Policies**: Automatic retries with backoff strategies
- **Custom Auth**: Scriptblock-based authentication handlers
- **File Uploads** : MultipartFormData with files


## Installation

```powershell
Install-Module PoshRest -Scope CurrentUser
```

## Basic Usage

```powershell
Import-Module PoshRest

# Create client with base URL
$client = [PoshRest]::new("https://api.example.com/v1")

# Configure defaults
$client.AddDefaultHeader("X-API-Key", "your-api-key").SetAuthentication("Bearer", "your-token").ConfigureRetry(5, [TimeSpan]::FromSeconds(2)).EnableCache()

# Create request with URL segment
$request = [PoshRestRequest]::new("users/{id}", [HttpMethod]::Get)
$request
    .AddParameter("id", 123, [ParameterType]::UrlSegment)
    .AddHeader("Accept", "application/json")

# Execute synchronously
$response = $client.Execute($request)

if ($response.IsSuccessful) {
    $user = $response.Content | ConvertFrom-Json
    Write-Host "User: $($user.name)"
} else {
    Write-Error "Request failed: $($response.StatusCode)"
}
```

## Feature Examples

### 1. Chainable Configuration

  ```powershell
  $client = [PoshRest]::new("https://api.example.com")
      .AddDefaultHeader("User-Agent", "MyApp/1.0")
      .AddDefaultParameter("api-version", "2.0", [ParameterType]::QueryString)
  ```

### 2. All Parameter Types

  ```powershell
  $request = [PoshRestRequest]::new("data", [HttpMethod]::Post)
  $request
      .AddParameter("page", 2, [ParameterType]::QueryString)
      .AddParameter("auth", "token", [ParameterType]::Header)
      .AddParameter("userId", 456, [ParameterType]::UrlSegment)
      .AddParameter("rememberMe", $true, [ParameterType]::Cookie)
      .AddBody(@{name="John"; age=30})
  ```

### 3. XML/JSON Serialization

  ```powershell
  # JSON with custom options
  $client.JsonOptions.PropertyNamingPolicy = [JsonNamingPolicy]::SnakeCase

  # XML with namespaces
  $client.ConfigureXml(
      [XmlSerializerNamespaces]::new(@([XmlQualifiedName]::new("ns", "http://example.com"))),
      [XmlWriterSettings]::new() | Add-Member -MemberType NoteProperty -Name Indent -Value $true
  )

  $request.AddXmlBody([PSCustomObject]@{Name="John"; Age=30})
  ```

### 4. Cookie Management

  ```powershell
  $client.AddCookie("session", "abc123", "api.example.com", "/api")
  ```

### 5. File Upload

  ```powershell
  $request = [PoshRestRequest]::new("uploads", [HttpMethod]::Post)
  $request
      .AddFile("profile", "C:\profile.jpg") |
      .AddBody(@{userId=123})
  ```

### 6. Retry Policies

  ```powershell
  $client.ConfigureRetry(3, [TimeSpan]::FromSeconds(1))
  ```

### 7. Caching

  ```powershell
  $client.EnableCache()
  $client.Execute([PoshRestRequest]::new("cached-data", [HttpMethod]::Get))
  ```

### 8. Custom Authentication

  ```powershell
  $client.SetAuthenticator({
      param($req)
      $req.RequestMessage.Headers.Add("X-Dynamic-Header", (Get-Random))
  })
  ```

### 9. URL Segments

  ```powershell
  $request = [PoshRestRequest]::new("products/{category}/{id}", [HttpMethod]::Get)
  $request
      .AddParameter("category", "electronics", [ParameterType]::UrlSegment)
      .AddParameter("id", 789, [ParameterType]::UrlSegment)
  ```

### 10. Async Execution

  ```powershell
  $client.ExecuteAsync($request) | Wait-Job | Receive-Job
  ```


## Community

@[GitHub Discussions](https://github.com/chadnpc/PoshRest/discussions) are open for Feature requests & Troubleshooting help.

## License

Released under the [WTFPL License 🍷🗿](LICENSE).