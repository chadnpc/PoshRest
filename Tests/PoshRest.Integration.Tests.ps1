Describe "Integration tests: PoshRest" {
  Context "Full Workflow" {
    BeforeAll {
      $tempFile = New-TemporaryFile
      "TestContent" | Out-File -FilePath $tempFile.FullName -Encoding utf8
      $mockClient = [PoshRest]::new("https://api.restful-api.dev") | EnableCache
      $mockClient.SetAuthentication("Bearer", "test-token")
      $mockClient.AddDefaultHeader("X-Custom-Header", "value")
      $mockClient.RetryPolicy.MaxRetries = 1
      $mockClient.Client = [HttpClient]::new([HttpClientHandler]::new())
    }

    It "Executes a complex request with all features" {
      $mockClient.Client.SendAsync = {
        param($request)
        $request.Headers.Authorization.Scheme | Should -Be "Bearer"
        $request.Headers.GetValues("X-Custom-Header") | Should -Contain "value"
        return [HttpResponseMessage]::new([HttpStatusCode]::OK)
      }

      $request = [PoshRestRequest]::new("upload", [HttpMethod]::Post)
      $request.AddFile("file", $tempFile.FullName)
      $request.AddBody(@{name = "TestFile" })

      $response = $mockClient.Execute($request)
      $response.StatusCode | Should -Be 200
    }
  }

  Context "Error Handling" {
    It "Handles invalid URL segments" {
      $client = [PoshRest]::new("https://api.restful-api.dev")
      $request = [PoshRestRequest]::new("users/{id}", [HttpMethod]::Get)
      { $client.BuildUri($request) } | Should -Throw "Missing URL segment 'id'"
    }
  }

  Context "Authentication" {
    It "Applies custom authenticators" {
      $client = [PoshRest]::new("https://api.restful-api.dev")
      $client.SetAuthenticator({
          param($req)
          $req.RequestMessage.Headers.Add("X-Dynamic", "value")
        })

      $request = [PoshRestRequest]::new("test", [HttpMethod]::Get)
      $client.PrepareRequest($request).RequestMessage.Headers.GetValues("X-Dynamic") | Should -Contain "value"
    }
  }
}