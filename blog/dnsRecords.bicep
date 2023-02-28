targetScope = 'resourceGroup'

@description('Domain name')
param domainName string

@description('Subdomain name e.g. www (optional)')
param subDomainName string = ''

@description('Custom domain verification ID.')
param customDomainVerificationId string

@description('IPv4 address for the App Service')
param appServiceIpAddress string

@description('Default host name for the App Service')
param appServiceDefaultHostName string

var isApex = empty(subDomainName)

resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' existing = {
  name: domainName

  // custom domain verification record
  resource verificationRecord 'TXT' = {
    name: isApex ? 'asuid' : 'asuid.${subDomainName}'
    properties: {
      TTL: 3600
      TXTRecords: [
        {
          value: [ customDomainVerificationId ]
        }
      ]
    }
  }

  // A record for apex domain
  resource aRecord 'A' = if (isApex) {
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

  // CNAME record for subdomain
  resource subDomainRecord 'CNAME' = if (!isApex) {
    name: isApex ? '@' : subDomainName
    properties: {
      TTL: 3600
      CNAMERecord: {
        cname: appServiceDefaultHostName
      }
    }
  }
}
