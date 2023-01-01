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
param databaseServerLogin string

@secure()
@description('Password for the MySQL server')
param databaseServerPassword string

var tags = {
  workload: appName
  environment: appEnv
}

var databaseServerName = 'dbsrv-${appName}-${appEnv}'

// MySQL server
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

output databaseServerHostname string = '${databaseServerName}.${privateDnsZone.name}}'
