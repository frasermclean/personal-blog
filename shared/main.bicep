@description('Location of non-global resources')
param location string = resourceGroup().location

@description('Domain name')
param domainName string

var tags = {
  workload: 'frasermclean'
  environment: 'shared'
}

resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' = {
  name: domainName
  location: 'global'
  tags: tags
}

output nameServers array = dnsZone.properties.nameServers
