@description('Application / workload name')
param appName string

@description('Application environment')
@allowed([ 'test', 'main' ])
param appEnv string

@description('Location for resources')
param location string = resourceGroup().location

@description('Name of the shared resource group')
param sharedResourceGroupName string

@description('User login for the MySQL server')
param databaseServerLogin string = 'dba_${uniqueString(resourceGroup().id)}'

@secure()
@description('Password for the MySQL server')
param databaseServerPassword string = newGuid()

var tags = {
  workload: appName
  environment: appEnv
}

@description('Subnet name for the app service')
var appServiceSubnetName = 'subnet-appService'

@description('Subnet name for the database')
var databaseSubnetName = 'subnet-database'

// virtual network
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-07-01' = {
  name: 'vnet-${appName}-${appEnv}'
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
          serviceEndpoints: [
            { service: 'Microsoft.KeyVault' }
          ]
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
  name: 'mysql-${appName}-${appEnv}'
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
    name: 'db-${appName}-${appEnv}'
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
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    virtualNetworkSubnetId: virtualNetwork::appServiceSubnet.id
    vnetRouteAllEnabled: true
    siteConfig: {
      linuxFxVersion: 'DOCKER|wordpress:latest'
      appSettings: [
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://hub.docker.com'
        }
        {
          name: 'WORDPRESS_DB_HOST'
          value: databaseServer.properties.fullyQualifiedDomainName
        }
        {
          name: 'WORDPRESS_DB_USER'
          value: databaseServer.properties.administratorLogin
        }
        {
          name: 'WORDPRESS_DB_PASSWORD'
          value: databaseServerPassword
        }
        {
          name: 'WORDPRESS_DB_NAME'
          value: databaseServer::database.name
        }
      ]
    }
  }
}
