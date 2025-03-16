Describe "Feature tests: PoshRest" {
  Context "Retry Policy" {
    It "Retries failed requests the specified number of times" {
      $mockClient = [PoshRest]::new("https://api.example.com")
      $mockClient.RetryPolicy.MaxRetries = 2

      $mockRequest = [PoshRestRequest]::new("test", [HttpMethod]::Get)

      # Mock HttpClient to return error then success
      $mockClient.Client = [HttpClient]::new([HttpClientHandler]::new())
      $mockClient.Client.SendAsync = {
        param($request)
        if ($request.RequestUri.Segments[-1] -eq "test") {
          if (++$script:invokeCount -le 2) {
            return [HttpResponseMessage]::new([HttpStatusCode]::ServiceUnavailable)
          } else {
            return [HttpResponseMessage]::new([HttpStatusCode]::OK)
          }
        }
      }

      $result = $mockClient.Execute($mockRequest)
      $result.StatusCode | Should -Be 200
      $script:invokeCount | Should -Be 3
    }
  }

  Context "Caching" {
    It "Caches GET requests" {
      $mockClient = [PoshRest]::new("https://api.example.com") | EnableCache
      $mockClient.Client = [HttpClient]::new([HttpClientHandler]::new())

      $mockRequest = [PoshRestRequest]::new("cache-test", [HttpMethod]::Get)
      $mockClient.Client.SendAsync = {
        return [HttpResponseMessage]::new([HttpStatusCode]::OK) | Add-Member -NotePropertyName Content -NotePropertyValue ([StringContent]::new("CachedResponse"))
      }

      $firstResponse = $mockClient.Execute($mockRequest)
      $secondResponse = $mockClient.Execute($mockRequest)

      $firstResponse.Content | Should -Be "CachedResponse"
      $secondResponse.Content | Should -Be "CachedResponse"
      $mockClient.Cache.Keys.Count | Should -Be 1
    }
  }

  Context "File Upload" {
    It "Sends files with form data" {
      $tempFile = New-TemporaryFile
      "TestContent" | Out-File -FilePath $tempFile.FullName -Encoding utf8

      $mockClient = [PoshRest]::new("https://api.example.com")
      $mockClient.Client = [HttpClient]::new([HttpClientHandler]::new())
      $mockClient.Client.SendAsync = { return [HttpResponseMessage]::new([HttpStatusCode]::OK) }

      $request = [PoshRestRequest]::new("upload", [HttpMethod]::Post)
      $request.AddFile("file", $tempFile.FullName)
      $request.AddBody(@{name = "TestFile" })

      $response = $mockClient.Execute($request)
      $response.StatusCode | Should -Be 200
    }
  }

  Context "XML Serialization" {
    It "Serializes objects to XML" {
      $mockClient = [PoshRest]::new("https://api.example.com")
      $mockClient.ConfigureXml([XmlSerializerNamespaces]::new(), [XmlWriterSettings]::new())

      $request = [PoshRestRequest]::new("xml", [HttpMethod]::Post)
      $request.AddXmlBody([PSCustomObject]@{Name = "John"; Age = 30 })

      $mockClient.Client.SendAsync = {
        $content = $_.RequestMessage.Content.ReadAsStringAsync().Result
        $content | Should -Match "<Name>John</Name>"
        return [HttpResponseMessage]::new([HttpStatusCode]::OK)
      }

      $mockClient.Execute($request)
    }
  }

  Context "URL Segments" {
    It "Replaces URL segments correctly" {
      $client = [PoshRest]::new("https://api.example.com")
      $request = [PoshRestRequest]::new("users/{id}/orders/{orderId}", [HttpMethod]::Get)
      $request.AddParameter("id", 123, [ParameterType]::UrlSegment)
      $request.AddParameter("orderId", 456, [ParameterType]::UrlSegment)

      $uri = $client.BuildUri($request)
      $uri.AbsoluteUri | Should -Be "https://api.example.com/users/123/orders/456"
    }
  }
}