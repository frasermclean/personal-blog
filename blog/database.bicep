targetScope = 'resourceGroup'

@description('Name of the database')
param databaseName string

// MySQL database server
resource databaseServer 'Microsoft.DBforMySQL/flexibleServers@2021-05-01' existing = {
  name: 'mysql-frasermclean-shared'

  // database
  resource database 'databases' = {
    name: databaseName
    properties: {
      charset: 'utf8'
      collation: 'utf8_general_ci'
    }
  }
}

@description('Database name')
output databaseName string = databaseServer::database.name

@description('Database server administrator login')
output databaseServerAdministratorLogin string = databaseServer.properties.administratorLogin

@description('Database server fully qualified domain name')
output databaseServerFullyQualifiedDomainName string = databaseServer.properties.fullyQualifiedDomainName
