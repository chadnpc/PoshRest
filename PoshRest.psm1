#!/usr/bin/env pwsh
using namespace System.IO
using namespace System.Xml
using namespace System.Net
using namespace System.Text
using namespace System.Xml.Linq
using namespace System.Net.Http
using namespace System.Text.Json
using namespace System.Collections
using namespace System.IO.Compression
using namespace System.Threading.Tasks
using namespace System.Net.Http.Headers
using namespace System.Xml.Serialization
using namespace System.Collections.Generic
using namespace System.Runtime.CompilerServices

#Requires -PSEdition Core

#region    Classes
enum ParameterType {
  RequestContent
  HttpContent
  FormField
  QueryString
  Header
  UrlSegment
  Cookie
  Body
}

enum HttpRequestMethod {
  GET 	  = 0
  POST 	  = 1
  PATCH   = 2
  PUT     = 3
  DELETE  = 4
  HEAD    = 5
  TRACE   = 6
  CONNECT = 7
  OPTIONS = 8
} # Read more details @ https://restful-api.dev/rest-fundamentals#rest

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

  [object] GetJsonObject() {
    if ([string]::IsNullOrWhiteSpace($this.Content)) { return $null }
    return $this.Content | ConvertFrom-Json
  }

  [object] GetJsonObject([Type]$type) {
    if ([string]::IsNullOrWhiteSpace($this.Content)) { return $null }
    $jsonObj = $this.Content | ConvertFrom-Json
    return $jsonObj -as $type
  }

  [object] GetXmlObject() {
    if ([string]::IsNullOrWhiteSpace($this.Content)) { return $null }
    $xmlDoc = [System.Xml.XmlDocument]::new()
    $xmlDoc.LoadXml($this.Content)
    return $xmlDoc
  }

  [object] GetXmlObject([Type]$type) {
    if ([string]::IsNullOrWhiteSpace($this.Content)) { return $null }
    $serializer = [XmlSerializer]::new($type)
    $reader = [System.IO.StringReader]::new($this.Content)
    $result = $serializer.Deserialize($reader)
    $reader.Close()
    return $result
  }

  [XElement] GetXElement() {
    if ([string]::IsNullOrWhiteSpace($this.Content)) { return $null }
    return [XElement]::Parse($this.Content)
  }
}

class PoshRestUtils {
  static [string] ReadContentAsStringGzip([HttpResponseMessage]$response) {
    # Check if response is compressed
    if ($response.Content.Headers.ContentEncoding -contains "gzip") {
      $stream = $response.Content.ReadAsStreamAsync().Result
      $decompressedStream = [GZipStream]::new($stream, [CompressionMode]::Decompress)
      $reader = [StreamReader]::new($decompressedStream)
      return $reader.ReadToEnd()
    }
    return $response.Content.ReadAsStringAsync().Result
  }

  static [Stream] ReadContentAsStreamGzip([HttpResponseMessage]$response) {
    # Check if response is compressed
    if ($response.Content.Headers.ContentEncoding -contains "gzip") {
      $stream = $response.Content.ReadAsStreamAsync().Result
      return [GZipStream]::new($stream, [CompressionMode]::Decompress)
    }
    return $response.Content.ReadAsStreamAsync().Result
  }

  static [void] ApplyAcceptEncodingGzip([HttpRequestMessage]$request) {
    $encodingMethod = "gzip"
    $found = $false

    foreach ($encoding in $request.Headers.AcceptEncoding) {
      if ($encodingMethod -eq $encoding.Value) {
        $found = $true
        break
      }
    }

    if (!$found) {
      $request.Headers.AcceptEncoding.Add([StringWithQualityHeaderValue]::new($encodingMethod))
    }
  }

  static [string] GetJsonString([object]$obj) {
    return ConvertTo-Json -InputObject $obj -Depth 100 -Compress
  }

  static [string] GetXmlString([object]$obj) {
    $serializer = [XmlSerializer]::new($obj.GetType())
    $stringWriter = [StringWriter]::new()
    $xmlWriter = [XmlWriter]::Create($stringWriter)
    $serializer.Serialize($xmlWriter, $obj)
    $xmlWriter.Close()
    return $stringWriter.ToString()
  }
}

class PoshRestRequest {
  [ValidateNotNull()][object]$Body
  [ValidateNotNull()][string]$Resource
  [ValidateNotNull()][HttpRequestMessage]$RequestMessage
  [ValidateNotNull()][Dictionary[string, string]]$Files = @{}
  [ValidateNotNull()][Dictionary[string, string]]$Headers = @{}
  [ValidateNotNull()][Dictionary[string, PoshRestParameter]]$Parameters = @{}

  PoshRestRequest([string]$resource, [string]$method) {
    if ($method -notin [Enum]::GetNames[HttpRequestMethod]()) {
      throw [System.ComponentModel.InvalidEnumArgumentException]::new("method", 0, [HttpRequestMethod])
    }
    $this.Resource = $resource
    $this.RequestMessage = [HttpRequestMessage]::new($method, "")
  }

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

# Similar to RequestPathAttribute in the inspiration
class RequestPath {
  [string]$Path

  RequestPath([string]$path) {
    $this.Path = $path
  }

  static [string] GetRequestPath([object]$requestObject) {
    $attribute = $requestObject.GetType().GetCustomAttributes([RequestPath], $true) | Select-Object -First 1
    if ($attribute) {
      return $attribute.Path
    }
    return [string]::Empty
  }

  static [string] GetRequestPath([Type]$requestType) {
    $attribute = $requestType.GetCustomAttributes([RequestPath], $true) | Select-Object -First 1
    if ($attribute) {
      return $attribute.Path
    }
    return [string]::Empty
  }
}

class PoshRest {
  [string]$BaseUrl
  [HttpClient]$Client
  [HttpClientHandler]$Handler
  [AuthenticationHeaderValue]$Auth
  [Dictionary[string, object]]$DefaultParameters = @{}
  [Dictionary[string, string]]$DefaultHeaders = @{}
  [Dictionary[string, string]]$Files = @{}
  [ValidateNotNullOrWhiteSpace()][string]$UserAgent
  [ValidateNotNullOrWhiteSpace()][string]$ContentType
  [JsonSerializerOptions]$JsonOptions
  [XmlSerializerNamespaces]$XmlNamespaces
  [XmlWriterSettings]$XmlWriterSettings
  [Dictionary[string, PoshRestResponse]]$Cache = @{}
  static [HttpResponseMessage[]]$session_resps = @()
  [PoshRestRetryPolicy]$RetryPolicy
  [bool]$UseCompression = $false

  PoshRest() {
    $this.__init__()
  }
  PoshRest([string]$baseUrl) {
    $this.BaseUrl = $baseUrl.TrimEnd('/')
    $this.__init__()
  }
  # Configuration Methods
  [PoshRest] AddDefaultHeader([string]$name, [string]$value) {
    [ValidateNotNullOrWhiteSpace()][string]$name = $name
    $this.DefaultHeaders[$name] = $value
    return $this
  }

  [PoshRest] AddDefaultParameter([string]$name, [object]$value, [ParameterType]$type) {
    [ValidateNotNullOrWhiteSpace()][string]$name = $name
    $this.DefaultParameters[$name] = @{ Value = $value; Type = $type }
    return $this
  }
  [PoshRest] AddCookie([string]$name, [string]$value) {
    return $this.AddCookie($name, $value, $null, $null)
  }
  [PoshRest] AddCookie([string]$name, [string]$value, [string]$domain, [string]$path) {
    [ValidateNotNullOrWhiteSpace()][string]$name = $name
    $cookie = New-Object System.Net.Cookie($name, $value, $path, $domain)
    $this.Handler.CookieContainer.Add($cookie)
    return $this
  }

  [PoshRest] SetAuthentication([string]$scheme, [string]$parameter) {
    [ValidateNotNullOrWhiteSpace()][string]$scheme = $scheme
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
  [PoshRest] ConfigureRetry() {
    return $this.ConfigureRetry(3, [TimeSpan]::FromSeconds(1))
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
  [PoshRest] EnableCompression() {
    $this.UseCompression = $true
    return $this
  }
  [PoshRestResponse] SendJsonRequest([HttpRequestMethod]$method, [Uri]$uri) {
    return $this.SendJsonRequest([HttpMethod]::new("$method"), $uri, $null)
  }
  [PoshRestResponse] SendJsonRequest([HttpMethod]$method, [Uri]$uri) {
    return $this.SendJsonRequest($method, $uri, $null)
  }
  [PoshRestResponse] SendJsonRequest([HttpRequestMethod]$method, [Uri]$uri, [object]$body) {
    return $this.SendJsonRequest([HttpMethod]::new("$method"), $uri, $body)
  }
  [PoshRestResponse] SendJsonRequest([HttpMethod]$method, [Uri]$uri, [object]$body) {
    $request = [PoshRestRequest]::new("", $method)
    $request.RequestMessage.RequestUri = $uri
    if ($null -ne $body -and @{} -ne $body) {
      $request.AddJsonBody($body)
    }
    return $this.Execute($request)
  }
  [PoshRestResponse] SendXmlRequest([HttpMethod]$method, [Uri]$uri, [object]$body) {
    $request = [PoshRestRequest]::new("", $method)
    $request.RequestMessage.RequestUri = $uri
    if ($body) {
      $request.AddXmlBody($body)
    }
    return $this.Execute($request)
  }

  # Methods for RequestPath
  [PoshRestResponse] ExecuteWithRequestPath([object]$requestObject) {
    $path = [RequestPath]::GetRequestPath($requestObject)
    if ([string]::IsNullOrEmpty($path)) {
      throw "Request object does not have a RequestPath attribute"
    }

    $request = [PoshRestRequest]::new($path, [HttpMethod]::Get)
    if ($requestObject -is [IDictionary]) {
      $request.AddJsonBody($requestObject)
    } else {
      $request.AddJsonBody([PSCustomObject]$requestObject)
    }

    return $this.Execute($request)
  }

  [PoshRestResponse] Execute([PoshRestRequest]$request) {
    $retryCount = 0; $response = $null

    while ($true) {
      $preparedRequest = $this.PrepareRequest($request)

      if ($this.UseCompression) {
        [PoshRestUtils]::ApplyAcceptEncodingGzip($preparedRequest.RequestMessage)
      }

      try {
        [Task[HttpResponseMessage]]$task = $this.Client.SendAsync($preparedRequest.RequestMessage)
        $awaiter = [TaskAwaiter]$task.GetAwaiter()
        $response = $awaiter.GetResult()
        [PoshRest]::results += $response
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
    return $null
    # Handle compressed response if needed
    $responseResult = if ($this.UseCompression) {
      $content = [PoshRestUtils]::ReadContentAsStringGzip($response)
      $responseObj = [PoshRestResponse]::new($response)
      $responseObj.Content = $content
      $responseObj
    } else {
      [PoshRestResponse]::new($response)
    }

    if ($this.Cache -and $request.RequestMessage.Method -eq [HttpMethod]::Get) {
      $cacheKey = "$($request.RequestMessage.RequestUri)::$($request.RequestMessage.Method)"
      $this.Cache[$cacheKey] = $responseResult
    }

    return $responseResult
  }
  # [Task[PoshRestResponse]] ExecuteAsync([PoshRestRequest]$request) {}

  [PoshRestRequest] PrepareRequest([PoshRestRequest]$request) {
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
  hidden [void] __init__() {
    $this.UserAgent = $this.GetType().Name
    $this.ContentType = "application/json"
    $this.Handler = [HttpClientHandler]::new()
    $this.Handler.CookieContainer = [CookieContainer]::new()
    $this.Client = [HttpClient]::new($this.Handler)
    $this.JsonOptions = [JsonSerializerOptions]::new()
    $this.JsonOptions.PropertyNamingPolicy = [JsonNamingPolicy]::CamelCase
    $this.JsonOptions.WriteIndented = $true
    $this.RetryPolicy = [PoshRestRetryPolicy]::new()
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
      if (!$request.Headers.ContainsKey($header.Key)) {
        $request.RequestMessage.Headers.Add($header.Key, $header.Value)
      }
    }
    if ([string]::IsNullOrWhiteSpace($this.UserAgent)) { $this.UserAgent = $this.GetType().Name }
    $request.RequestMessage.Headers.UserAgent.ParseAdd($this.UserAgent)
    $request.RequestMessage.Headers.Accept.Add([MediaTypeWithQualityHeaderValue]::new($this.ContentType))
  }

  hidden [void] ApplyAuthentication([PoshRestRequest]$request) {
    if ($this.Auth) {
      $request.RequestMessage.Headers.Authorization = $this.Auth
    }
  }

  hidden [void] ApplyBody([PoshRestRequest]$request) {
    if (!$request.Body -and !$request.Files.Count) { return }

    $content = switch ($true) {
      $($request.Files.Count -gt 0) {
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
  [PoshRest], [PoshRestParameter], [HttpRequestMethod], [PoshRestRequest],
  [PoshRestResponse], [PoshRestRetryPolicy], [ParameterType], [PoshRestUtils], [RequestPath]
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
