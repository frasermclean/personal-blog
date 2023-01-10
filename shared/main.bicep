targetScope = 'resourceGroup'

@description('Domain name')
param domainName string

@description('Location of non-global resources')
param location string = resourceGroup().location

@description('Workload name for tagging and resource naming purposes')
param workload string = 'frasermclean'

@description('Environment name for tagging and resource naming purposes')
param env string = 'shared'

var tags = {
  workload: workload
  environment: env
}

var storageAccountName = 'st${workload}${env}'

// dns zone
resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' = {
  name: domainName
  location: 'global'
  tags: tags

  resource storageAccountCnameRecord 'CNAME' = {
    name: 'blob'
    properties: {
      TTL: 3600
      CNAMERecord: {
        cname: '${storageAccountName}.blob.${environment().suffixes.storage}'
      }
    }
  }
}

// storage account for the app service
resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    allowCrossTenantReplication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    encryption: {
      requireInfrastructureEncryption: false
      keySource: 'Microsoft.Storage'
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
    }
    customDomain: {
      name: 'blob.${domainName}'
    }
  }

  resource blobServices 'blobServices' = {
    name: 'default'

    // public container for hosting static content
    resource container 'containers' = {
      name: 'public'
      properties: {
        publicAccess: 'Blob'
      }
    }
  }
}

output nameServers array = dnsZone.properties.nameServers
