targetScope = 'resourceGroup'

@description('DNS zone name.')
param dnsZoneName string

param subDomainName string = ''

@description('Custom domain apex validation token.')
param validationToken string

@description('Front Door endpoint host name.')
param frontdoorEndpointHostName string

var isApex = empty(subDomainName)

resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' existing = {
  name: dnsZoneName

  // TXT record for custom domain validation
  resource txtRecord 'TXT' = {
    name: isApex ? '_dnsauth' : '_dnsauth.${subDomainName}'
    properties: {
      TTL: 3600
      TXTRecords: [
        {
          value: [
            validationToken
          ]
        }
      ]
    }
  }

  // CNAME record for custom domain
  resource cnameRecord 'CNAME' = if (!isApex) {
    name: subDomainName
    properties: {
      TTL: 3600
      CNAMERecord: {
        cname: frontdoorEndpointHostName
      }
    }
  }
}
