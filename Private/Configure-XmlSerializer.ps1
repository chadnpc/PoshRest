function Configure-XmlSerializer {
  param(
    [Parameter(Mandatory)]
    [PoshRest]$Client,

    [string]$Namespace = "",
    [switch]$OmitXmlDeclaration
  )
  $xmlSettings = [XmlWriterSettings]::new()
  $xmlSettings.OmitXmlDeclaration = $OmitXmlDeclaration
  $client.ConfigureXml(
    [XmlSerializerNamespaces]::new(),
    $xmlSettings
  )
}