#!/usr/bin/env pwsh
using namespace System.Xml
using namespace System.Net
using namespace System.Text
using namespace System.Net.Http
using namespace System.Text.Json
using namespace System.Collections
using namespace System.Net.Http.Headers
using namespace System.Xml.Serialization
using namespace System.Collections.Generic

#region    Classes
enum ParameterType {
  QueryString
  Header
  UrlSegment
  Cookie
  Body
}
class PoshRestRetryPolicy {
  [int]$MaxRetries = 3
  [TimeSpan]$Delay = [TimeSpan]::FromSeconds(1)
}
class PoshRestParameter {
  [string]$Name
  [object]$Value
  [ParameterType]$Type

  PoshRestParameter([string]$name, [object]$value, [ParameterType]$type) {
    $this.Name = $name
    $this.Value = $value
    $this.Type = $type
  }
}
class PoshRestResponse {
  [int]$StatusCode
  [string]$Content
  [string]$ErrorMessage
  [bool]$IsSuccessful
  [Dictionary[string, IEnumerable[string]]]$Headers = @{}

  PoshRestResponse([HttpResponseMessage]$response) {
    $this.StatusCode = [int]$response.StatusCode
    $this.IsSuccessful = $response.IsSuccessStatusCode
    $this.Content = $response.Content.ReadAsStringAsync().Result
    foreach ($header in $response.Headers) {
      $this.Headers[$header.Key] = $header.Value
    }
  }
}
class PoshRestRequest {
  [HttpRequestMessage]$RequestMessage
  [string]$Resource
  [Dictionary[string, PoshRestParameter]]$Parameters = @{}
  [object]$Body
  [Dictionary[string, string]]$Headers = @{}
  [Dictionary[string, string]]$Files = @{}

  PoshRestRequest([string]$resource, [HttpMethod]$method) {
    $this.Resource = $resource
    $this.RequestMessage = [HttpRequestMessage]::new($method, "")
  }

  [PoshRestRequest] AddHeader([string]$name, [string]$value) {
    $this.Headers[$name] = $value
    $this.RequestMessage.Headers.Add($name, $value)
    return $this
  }

  [PoshRestRequest] AddParameter([string]$name, [object]$value, [ParameterType]$type) {
    $this.Parameters[$name] = [PoshRestParameter]::new($name, $value, $type)
    return $this
  }

  [PoshRestRequest] AddFile([string]$name, [string]$filePath) {
    $this.Files[$name] = $filePath
    return $this
  }

  [PoshRestRequest] AddBody([object]$body) {
    $this.Body = $body
    return $this
  }

  [PoshRestRequest] AddJsonBody([object]$body) {
    $this.Body = $body
    $this.AddHeader("Content-Type", "application/json")
    return $this
  }

  [PoshRestRequest] AddXmlBody([object]$body) {
    $this.Body = $body
    $this.AddHeader("Content-Type", "application/xml")
    return $this
  }
}

class PoshRest {
  [HttpClient]$Client
  [HttpClientHandler]$Handler
  [string]$BaseUrl
  [Dictionary[string, object]]$DefaultParameters = @{}
  [Dictionary[string, string]]$DefaultHeaders = @{}
  [Dictionary[string, string]]$Files = @{}
  [AuthenticationHeaderValue]$Auth
  [string]$ContentType = "application/json"
  [string]$UserAgent = "PoshRest/0.1.0"
  [JsonSerializerOptions]$JsonOptions
  [XmlSerializerNamespaces]$XmlNamespaces
  [XmlWriterSettings]$XmlWriterSettings
  [Dictionary[string, PoshRestResponse]]$Cache = @{}
  [PoshRestRetryPolicy]$RetryPolicy

  PoshRest([string]$baseUrl) {
    $this.BaseUrl = $baseUrl.TrimEnd('/')
    $this.Handler = [HttpClientHandler]::new()
    $this.Handler.CookieContainer = [CookieContainer]::new()
    $this.Client = [HttpClient]::new($this.Handler)
    $this.JsonOptions = [JsonSerializerOptions]::new()
    $this.JsonOptions.PropertyNamingPolicy = [JsonNamingPolicy]::CamelCase
    $this.JsonOptions.WriteIndented = $true
    $this.RetryPolicy = [PoshRestRetryPolicy]::new()
  }

  # Configuration Methods
  [PoshRest] AddDefaultHeader([string]$name, [string]$value) {
    $this.DefaultHeaders[$name] = $value
    return $this
  }

  [PoshRest] AddDefaultParameter([string]$name, [object]$value, [ParameterType]$type) {
    $this.DefaultParameters[$name] = @{ Value = $value; Type = $type }
    return $this
  }

  [PoshRest] AddCookie([string]$name, [string]$value, [string]$domain = $null, [string]$path = $null) {
    $cookie = New-Object System.Net.Cookie($name, $value, $path, $domain)
    $this.Handler.CookieContainer.Add($cookie)
    return $this
  }

  [PoshRest] SetAuthentication([string]$scheme, [string]$parameter) {
    $this.Auth = [AuthenticationHeaderValue]::new($scheme, $parameter)
    return $this
  }

  [PoshRest] SetAuthenticator([ScriptBlock]$auth) {
    $this.Authenticator = $auth
    return $this
  }

  [PoshRest] SetTimeout([TimeSpan]$timeout) {
    $this.Client.Timeout = $timeout
    return $this
  }

  [PoshRest] ConfigureXml([XmlSerializerNamespaces]$namespaces, [XmlWriterSettings]$settings) {
    $this.XmlNamespaces = $namespaces
    $this.XmlWriterSettings = $settings
    return $this
  }

  [PoshRest] ConfigureRetry([int]$maxRetries = 3, [TimeSpan]$delay = [TimeSpan]::FromSeconds(1)) {
    $this.RetryPolicy.MaxRetries = $maxRetries
    $this.RetryPolicy.Delay = $delay
    return $this
  }

  [PoshRest] EnableCache() {
    $this.Cache = [Dictionary[string, PoshRestResponse]]::new()
    return $this
  }

  # Request Execution
  [PoshRestResponse] Execute([PoshRestRequest]$request) {
    return $this.ExecuteAsync($request).GetAwaiter().GetResult()
  }

  hidden [PoshRestResponse] ExecuteSync([PoshRestRequest]$request) {
    return $this.ExecuteAsync($request).GetAwaiter().GetResult()
  }

  [PoshRestResponse] ExecuteAsync([PoshRestRequest]$request) {
    $retryCount = 0; $response = $null

    while ($true) {
      $preparedRequest = $this.PrepareRequest($request)
      try {
        $response = await $this.Client.SendAsync($preparedRequest.RequestMessage)
      } catch {
        if ($retryCount -ge $this.RetryPolicy.MaxRetries) { throw }
        Start-Sleep -Milliseconds $this.RetryPolicy.Delay.TotalMilliseconds
        $retryCount++
        continue
      }

      if ($response.IsSuccessStatusCode -or $retryCount -ge $this.RetryPolicy.MaxRetries) {
        break
      }

      if ($response.StatusCode -ge 500 -and $response.StatusCode -le 599) {
        Start-Sleep -Milliseconds $this.RetryPolicy.Delay.TotalMilliseconds
        $retryCount++
      } else {
        break
      }
    }

    $responseResult = [PoshRestResponse]::new($response)

    if ($this.Cache -and $request.RequestMessage.Method -eq [HttpMethod]::Get) {
      $cacheKey = "$($request.RequestMessage.RequestUri)::$($request.RequestMessage.Method)"
      $this.Cache[$cacheKey] = $responseResult
    }

    return $responseResult
  }

  # Request Preparation
  hidden [PoshRestRequest] PrepareRequest([PoshRestRequest]$request) {
    $uri = $this.BuildUri($request)
    $request.RequestMessage.RequestUri = $uri

    $this.ApplyDefaultHeaders($request)
    $this.ApplyAuthentication($request)
    $this.ApplyBody($request)

    if ($this.Authenticator) {
      & $this.Authenticator.Invoke($request)
    }

    return $request
  }

  hidden [Uri] BuildUri([PoshRestRequest]$request) {
    $resourcePath = $request.Resource
    foreach ($param in $this.DefaultParameters.Values + $request.Parameters.Values) {
      if ($param.Type -eq [ParameterType]::UrlSegment) {
        $escapedName = [Regex]::Escape($param.Name)
        $value = [Uri]::EscapeDataString($param.Value.ToString())
        $resourcePath = $resourcePath -replace "\{$escapedName\}", $value
      }
    }

    $url = "$($this.BaseUrl)/$($resourcePath.TrimStart('/'))"

    $queryParams = [List[string]]::new()
    foreach ($param in $this.DefaultParameters.Values + $request.Parameters.Values) {
      if ($param.Type -eq [ParameterType]::QueryString) {
        $queryParams.Add("$($param.Name)=$([Uri]::EscapeDataString($param.Value.ToString()))")
      }
    }

    if ($queryParams.Count -gt 0) {
      $url += "?" + ($queryParams -join '&')
    }

    return [Uri]::new($url)
  }

  hidden [void] ApplyDefaultHeaders([PoshRestRequest]$request) {
    foreach ($header in $this.DefaultHeaders.GetEnumerator()) {
      if (-not $request.Headers.ContainsKey($header.Key)) {
        $request.RequestMessage.Headers.Add($header.Key, $header.Value)
      }
    }

    $request.RequestMessage.Headers.UserAgent.ParseAdd($this.UserAgent)
    $request.RequestMessage.Headers.Accept.Add([MediaTypeWithQualityHeaderValue]::new($this.ContentType))
  }

  hidden [void] ApplyAuthentication([PoshRestRequest]$request) {
    if ($this.Auth) {
      $request.RequestMessage.Headers.Authorization = $this.Auth
    }
  }

  hidden [void] ApplyBody([PoshRestRequest]$request) {
    if (-not $request.Body -and -not $request.Files.Count) { return }

    $content = switch ($true) {
            ($request.Files.Count -gt 0) {
        $formData = [MultipartFormDataContent]::new()
        if ($request.Body -is [IDictionary]) {
          foreach ($key in $request.Body.Keys) {
            $formData.Add([StringContent]$request.Body[$key].ToString(), $key)
          }
        }
        foreach ($file in $request.Files.GetEnumerator()) {
          $filePath = $file.Value
          $fileName = Split-Path $filePath -Leaf
          $fileStream = [System.IO.File]::OpenRead($filePath)
          $fileContent = [StreamContent]::new($fileStream)
          $fileContent.Headers.ContentType = [MediaTypeHeaderValue]::Parse("application/octet-stream")
          $formData.Add($fileContent, $file.Key, $fileName)
        }
        $formData
      }
      default {
        if ($request.Headers["Content-Type"] -eq "application/xml" -or $this.ContentType -eq "application/xml") {
          $xmlSerializer = [XmlSerializer]$request.Body.GetType()
          $xmlSettings = $this.XmlWriterSettings ?? [XmlWriterSettings]::new()
          $xmlSettings.Indent = $true
          $ms = [IO.MemoryStream]::new()
          $writer = [XmlWriter]::Create($ms, $xmlSettings)
          $xmlSerializer.Serialize($writer, $request.Body)
          $writer.Flush()
          $ms.Position = 0
          $xmlContent = [IO.StreamReader]::new($ms).ReadToEnd()
          $ms.Dispose()
          $writer.Dispose()
          [StringContent]::new($xmlContent, [Encoding]::UTF8, "application/xml")
        } else {
          $json = [JsonSerializer]::Serialize($request.Body, $this.JsonOptions)
          [StringContent]::new($json, [Encoding]::UTF8, "application/json")
        }
      }
    }

    $request.RequestMessage.Content = $content
  }
}
#endregion Classes
# Types that will be available to users when they import the module.
$typestoExport = @(
  [PoshRest], [PoshRestParameter], [PoshRestRequest], [PoshRestResponse], [PoshRestRetryPolicy], [ParameterType]
)
$TypeAcceleratorsClass = [PsObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
foreach ($Type in $typestoExport) {
  if ($Type.FullName -in $TypeAcceleratorsClass::Get.Keys) {
    $Message = @(
      "Unable to register type accelerator '$($Type.FullName)'"
      'Accelerator already exists.'
    ) -join ' - '
    "TypeAcceleratorAlreadyExists $Message" | Write-Debug
  }
}
# Add type accelerators for every exportable type.
foreach ($Type in $typestoExport) {
  $TypeAcceleratorsClass::Add($Type.FullName, $Type)
}
# Remove type accelerators when the module is removed.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
  foreach ($Type in $typestoExport) {
    $TypeAcceleratorsClass::Remove($Type.FullName)
  }
}.GetNewClosure();

$scripts = @();
$Public = Get-ChildItem "$PSScriptRoot/Public" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += Get-ChildItem "$PSScriptRoot/Private" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$scripts += $Public

foreach ($file in $scripts) {
  Try {
    if ([string]::IsNullOrWhiteSpace($file.fullname)) { continue }
    . "$($file.fullname)"
  } Catch {
    Write-Warning "Failed to import function $($file.BaseName): $_"
    $host.UI.WriteErrorLine($_)
  }
}

$Param = @{
  Function = $Public.BaseName
  Cmdlet   = '*'
  Alias    = '*'
  Verbose  = $false
}
Export-ModuleMember @Param
