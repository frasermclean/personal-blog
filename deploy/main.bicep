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
  }
}
