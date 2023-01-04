@description('Name of the workload / application')
param appName string

@description('Application environment')
@allowed([
  'main'
  'test'
])
param appEnv string = 'main'

@description('Location for resources')
param location string = resourceGroup().location

@description('User login for the MySQL server')
param databaseServerLogin string = 'dba_${uniqueString(resourceGroup().id)}'

@secure()
@description('Password for the MySQL server')
param databaseServerPassword string = newGuid()

@description('Domain name for the WordPress site')
param domainName string = 'frasermclean.com'

@description('User name for the WordPress admin account')
param wordPressAdminUsername string = 'admin'

@secure()
@description('Password for the WordPress admin account')
param wordPressAdminPassword string

var tags = {
  workload: appName
  environment: appEnv
}

var databaseServerName = 'mysql-${appName}-${appEnv}'
var wordPressAdminEmail = '${wordPressAdminUsername}@${domainName}'

// storage account for the app service
resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: 'stg${appName}${appEnv}'
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
  }

  resource blobServices 'blobServices' = {
    name: 'default'

    // container for the app service
    resource container 'containers' = {
      name: appName
      properties: {
        publicAccess: 'Blob'
      }
    }
  }
}

// virtual network
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  name: 'vnet-${appName}-${appEnv}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'AppServiceSubnet'
        properties: {
          addressPrefix: '10.0.0.0/24'
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
        name: 'DatabaseSubnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
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
    name: 'AppServiceSubnet'
  }

  resource databaseSubnet 'subnets' existing = {
    name: 'DatabaseSubnet'
  }
}

// private DNS zone for MySQL server
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: '${appName}-${appEnv}.private.mysql.database.azure.com'
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
  name: databaseServerName
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

  // database
  resource database 'databases' = {
    name: appName
    properties: {
      charset: 'utf8'
      collation: 'utf8_general_ci'
    }
  }
}

// app service plan
resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: 'asp-${appName}-${appEnv}'
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: 'B1'
  }
  properties: {
    reserved: true
  }
}

// app service
resource appService 'Microsoft.Web/sites@2022-03-01' = {
  name: 'app-${appName}-${appEnv}'
  location: location
  tags: tags
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlan.id
    virtualNetworkSubnetId: virtualNetwork::appServiceSubnet.id
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'DOCKER|mcr.microsoft.com/appsvc/wordpress-alpine-php:latest'
      vnetRouteAllEnabled: true
      alwaysOn: true
      appSettings: [
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://mcr.microsoft.com'
        }
        {
          name: 'DATABASE_HOST'
          value: databaseServer.properties.fullyQualifiedDomainName
        }
        {
          name: 'DATABASE_NAME'
          value: databaseServer::database.name
        }
        {
          name: 'DATABASE_USERNAME'
          value: databaseServer.properties.administratorLogin
        }
        {
          name: 'DATABASE_PASSWORD'
          value: databaseServerPassword
        }
        {
          name: 'WORDPRESS_ADMIN_EMAIL'
          value: wordPressAdminEmail
        }
        {
          name: 'WORDPRESS_ADMIN_USER'
          value: wordPressAdminUsername
        }
        {
          name: 'WORDPRESS_ADMIN_PASSWORD'
          value: wordPressAdminPassword
        }
        {
          name: 'WORDPRESS_LOCALE_CODE'
          value: 'en_US'
        }
        {
          name: 'BLOB_CONTAINER_NAME'
          value: storageAccount::blobServices::container.name
        }
        {
          name: 'BLOB_STORAGE_ENABLED'
          value: 'true'
        }
        {
          name: 'BLOB_STORAGE_URL'
          value: '${storageAccount.name}.blob.${environment().suffixes.storage}'
        }
        {
          name: 'STORAGE_ACCOUNT_KEY'
          value: listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: storageAccount.name
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'true'
        }
        {
          name: 'AFD_ENABLED'
          value: 'true'
        }
        {
          name: 'AFD_ENDPOINT'
          value: afdProfile::endpoint.properties.hostName
        }
        {
          name: 'AFD_CUSTOM_DOMAIN'
          value: afdProfile::wwwCustomDomain.properties.hostName
        }
      ]
    }
  }
}

// azure front door profile
resource afdProfile 'Microsoft.Cdn/profiles@2021-06-01' = {
  name: 'afd-${appName}-${appEnv}'
  location: 'global'
  tags: tags
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }

  // endpoint
  resource endpoint 'afdEndpoints' = {
    name: 'fde-${appName}-${appEnv}'
    location: 'global'
    properties: {
      enabledState: 'Enabled'
    }

    resource route 'routes' = {
      name: 'route-${appName}-${appEnv}'
      dependsOn: [
        originGroup::origin // ensure origin is created before route
      ]
      properties: {
        forwardingProtocol: 'HttpsOnly'
        linkToDefaultDomain: 'Enabled'
        httpsRedirect: 'Enabled'
        originGroup: {
          id: originGroup.id
        }
        customDomains: [
          { id: apexCustomDomain.id }
          { id: wwwCustomDomain.id }
        ]
        supportedProtocols: [
          'Http'
          'Https'
        ]
        patternsToMatch: [
          '/*'
        ]
      }
    }
  }

  // origin group
  resource originGroup 'originGroups' = {
    name: 'og-${appName}-${appEnv}'
    properties: {
      loadBalancingSettings: {
        sampleSize: 4
        successfulSamplesRequired: 3
      }
      healthProbeSettings: {
        probePath: '/'
        probeRequestType: 'HEAD'
        probeProtocol: 'Http'
        probeIntervalInSeconds: 100
      }
    }

    // origin for app service
    resource origin 'origins' = {
      name: 'origin-${appName}-${appEnv}'
      properties: {
        hostName: appService.properties.defaultHostName
        httpPort: 80
        httpsPort: 443
        enabledState: 'Enabled'
        originHostHeader: appService.properties.defaultHostName
        priority: 1
        weight: 1000
      }
    }
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

// DNS records for apex custom domain
// module dnsRecords 'dnsRecords.bicep' = {
//   name: 'dnsRecords-${appName}-${appEnv}-apex'
//   scope: resourceGroup('rg-frasermclean-shared')
//   params: {
//     dnsZoneName: domainName
//     validationToken: afdProfile::apexCustomDomain.properties.validationProperties.validationToken
//     frontdoorEndpointHostName: afdProfile::endpoint.properties.hostName
//   }
// }

// DNS records for www custom domain
module dnsRecordsWww 'dnsRecords.bicep' = {
  name: 'dnsRecords-${appName}-${appEnv}-www'
  scope: resourceGroup('rg-frasermclean-shared')
  params: {
    dnsZoneName: domainName
    subDomainName: 'www'
    validationToken: afdProfile::wwwCustomDomain.properties.validationProperties.validationToken
    frontdoorEndpointHostName: afdProfile::endpoint.properties.hostName
  }
}

output appServiceHostName string = appService.properties.defaultHostName
output frontdoorEndpointHostName string = afdProfile::endpoint.properties.hostName
