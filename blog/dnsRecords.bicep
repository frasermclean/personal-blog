targetScope = 'resourceGroup'

param domainName string

@description('Custom domain verification ID.')
param verificationId string

@description('IPv4 address for the app service')
param appServiceIpAddress string

resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' existing = {
  name: domainName

  // custom domain verification
  resource verificationRecord 'TXT' = {
    name: 'asuid'
    properties: {
      TTL: 3600
      TXTRecords: [
        {
          value: [
            verificationId
          ]
        }
      ]
    }
  }

  resource aRecord 'A' = {
    name: '@'
    properties: {
      TTL: 3600
      ARecords: [
        {
          ipv4Address: appServiceIpAddress
        }
      ]
    }
  }
}
