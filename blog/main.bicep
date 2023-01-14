targetScope = 'resourceGroup'

@description('Name of the workload / application')
param workload string

@description('Location for resources')
param location string = resourceGroup().location

@description('Domain name for the WordPress site')
param domainName string

@description('Name of the shared resource group')
param sharedResourceGroupName string

@secure()
@description('Password for the MySQL server')
param databaseServerPassword string

@description('User name for the WordPress admin account')
param wordPressAdminUsername string = 'admin'

@secure()
@description('Password for the WordPress admin account')
param wordPressAdminPassword string

var tags = {
  workload: workload
}

var wordPressAdminEmail = '${wordPressAdminUsername}@${domainName}'

@description('Name of the MySQL database')
var databaseName = 'blog'

@description('Name of the app service')
var appServiceName = 'app-${workload}'

// storage account for the app service (existing)
resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' existing = {
  name: 'stfrasermcleanshared'
  scope: resourceGroup(sharedResourceGroupName)

  resource blobServices 'blobServices' existing = {
    name: 'default'

    // container for the app service
    resource publicContainer 'containers' existing = {
      name: 'public'
    }
  }
}

// virtual network (existing)
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-07-01' existing = {
  name: 'vnet-frasermclean-shared'
  scope: resourceGroup(sharedResourceGroupName)

  resource appServiceSubnet 'subnets' existing = {
    name: 'subnet-appService'
  }
}

// database
module database 'database.bicep' = {
  name: 'database-${workload}'
  scope: resourceGroup(sharedResourceGroupName)
  params: {
    databaseName: databaseName
  }
}

// azure front door endpoint
module frontDoor 'frontDoor.bicep' = {
  name: 'frontDoor-${workload}'
  scope: resourceGroup(sharedResourceGroupName)
  params: {
    workload: workload
    domainName: domainName
    appServiceName: appServiceName
    storageAccountName: storageAccount.name
    storageContainerName: storageAccount::blobServices::publicContainer.name
  }
}

// app service plan
resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: 'asp-${workload}'
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

// user assigned managed identity for the app service
resource appServiceIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: 'id-${workload}'
  location: location
  tags: tags
}

// app service
resource appService 'Microsoft.Web/sites@2022-03-01' = {
  name: appServiceName
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
          value: database.outputs.databaseServerFullyQualifiedDomainName
        }
        {
          name: 'DATABASE_NAME'
          value: database.outputs.databaseName
        }
        {
          name: 'DATABASE_USERNAME'
          value: database.outputs.databaseServerAdministratorLogin
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
          value: 'en_AU'
        }
        {
          name: 'BLOB_CONTAINER_NAME'
          value: storageAccount::blobServices::publicContainer.name
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
          value: frontDoor.outputs.endpointHostName
        }
        {
          name: 'AFD_CUSTOM_DOMAIN'
          value: frontDoor.outputs.endpointCustomDomain
        }
      ]
      ipSecurityRestrictions: [
        {
          name: 'Allow traffic from Front Door'
          tag: 'ServiceTag'
          ipAddress: 'AzureFrontDoor.Backend'
          action: 'Allow'
          priority: 100
          headers: {
            'x-azure-fdid': [
              frontDoor.outputs.frontDoorId
            ]
          }
        }
      ]
    }
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appServiceIdentity.id}': {}
    }
  }
}

module roleAssignment 'roleAssignment.bicep' = {
  name: 'roleAssignment-${workload}'
  scope: resourceGroup(sharedResourceGroupName)
  params: {
    principalId: appServiceIdentity.properties.principalId
    builtInRole: '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
  }
}
