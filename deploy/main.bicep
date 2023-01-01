@description('Name of the workload / application')
param workload string

@description('Location for resources')
param location string = resourceGroup().location

@description('User login for the MySQL server')
param databaseServerLogin string

@secure()
@description('Password for the MySQL server')
param databaseServerPassword string

var tags = {
  workload: workload
}

// MySQL server
resource databaseServer 'Microsoft.DBforMySQL/flexibleServers@2021-05-01' = {
  name: 'dbsrv-${workload}'
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
}
