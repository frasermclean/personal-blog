targetScope = 'resourceGroup'

@description('Domain name')
param domainName string

@description('Location of non-global resources')
param location string = resourceGroup().location

@description('Workload name for tagging and resource naming purposes')
param workload string = 'frasermclean'

@description('Environment name for tagging and resource naming purposes')
param env string = 'shared'

@description('User login for the MySQL server')
param databaseServerLogin string = 'dba_${uniqueString(resourceGroup().id)}'

@secure()
@description('Password for the MySQL server')
param databaseServerPassword string = newGuid()

var tags = {
  workload: workload
  environment: env
}

@description('Name of the storage account resource')
var storageAccountName = 'st${workload}${env}'

@description('Subnet name for the app service')
var appServiceSubnetName = 'subnet-appService'

@description('Subnet name for the database')
var databaseSubnetName = 'subnet-database'

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

  // azure front door custom domain validation for apex domain
  resource apexCustomDomainAuthorizationRecord 'CNAME' = {
    name: '_dnsauth'
    properties: {
      TTL: 3600
      CNAMERecord: {
        cname: afdProfile::apexCustomDomain.properties.validationProperties.validationToken
      }
    }
  }

  // azure front door custom domain validation for www subdomain
  resource wwwCustomDomainAuthorizationRecord 'CNAME' = {
    name: '_dnsauth.www'
    properties: {
      TTL: 3600
      CNAMERecord: {
        cname: afdProfile::wwwCustomDomain.properties.validationProperties.validationToken
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

// virtual network
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  name: 'vnet-${workload}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: appServiceSubnetName
        properties: {
          addressPrefix: '10.1.1.0/24'
          delegations: [
            {
              name: 'dlg-appService'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: databaseSubnetName
        properties: {
          addressPrefix: '10.1.2.0/24'
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          delegations: [
            {
              name: 'dlg-database'
              properties: {
                serviceName: 'Microsoft.DBforMySQL/flexibleServers'
              }
            }
          ]
        }
      }
    ]
  }

  resource appServiceSubnet 'subnets' existing = {
    name: appServiceSubnetName
  }

  resource databaseSubnet 'subnets' existing = {
    name: databaseSubnetName
  }
}

// private DNS zone for MySQL server
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: '${workload}.private.mysql.database.azure.com'
  location: 'global'

  resource virtualNetworkLink 'virtualNetworkLinks' = {
    name: virtualNetwork.name
    location: 'global'
    properties: {
      registrationEnabled: true
      virtualNetwork: {
        id: virtualNetwork.id
      }
    }
  }
}

// MySQL database server
resource databaseServer 'Microsoft.DBforMySQL/flexibleServers@2021-05-01' = {
  name: 'mysql-${workload}-${env}'
  location: location
  tags: tags
  sku: {
    name: 'Standard_B1s'
    tier: 'Burstable'
  }
  properties: {
    version: '8.0.21'
    administratorLogin: databaseServerLogin
    administratorLoginPassword: databaseServerPassword
    storage: {
      storageSizeGB: 20
      iops: 360
      autoGrow: 'Enabled'
    }
    network: {
      privateDnsZoneResourceId: privateDnsZone.id
      delegatedSubnetResourceId: virtualNetwork::databaseSubnet.id
    }
  }
  dependsOn: [
    privateDnsZone::virtualNetworkLink
  ]
}

// azure front door profile
resource afdProfile 'Microsoft.Cdn/profiles@2021-06-01' = {
  name: 'afd-${workload}-${env}'
  location: 'global'
  tags: tags
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }

  // apex custom domain
  resource apexCustomDomain 'customDomains' = {
    name: replace(domainName, '.', '-')
    properties: {
      hostName: domainName
      tlsSettings: {
        certificateType: 'ManagedCertificate'
        minimumTlsVersion: 'TLS12'
      }
    }
  }

  // www custom domain
  resource wwwCustomDomain 'customDomains' = {
    name: replace('www.${domainName}', '.', '-')
    properties: {
      hostName: 'www.${domainName}'
      tlsSettings: {
        certificateType: 'ManagedCertificate'
        minimumTlsVersion: 'TLS12'
      }
    }
  }
}