targetScope = 'resourceGroup'

@description('Name of the workload / application')
param workload string

@description('Location for resources')
param location string = resourceGroup().location

@description('Domain name for the WordPress site')
param domainName string

@description('Custom subdomains to create DNS records for')
param subDomains array = [ '', 'www' ]

@description('Name of the shared resource group')
param sharedResourceGroupName string

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

// virtual network (existing)
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-07-01' existing = {
  name: 'vnet-frasermclean-shared'
  scope: resourceGroup(sharedResourceGroupName)

  resource appServiceSubnet 'subnets' existing = {
    name: 'subnet-appService'
  }
}

// key vault (existing)
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: 'kv-frasermclean-shared'
  scope: resourceGroup(sharedResourceGroupName)
}

// database
module database 'database.bicep' = {
  name: 'database-${workload}'
  scope: resourceGroup(sharedResourceGroupName)
  params: {
    databaseName: databaseName
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
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appServiceIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    virtualNetworkSubnetId: virtualNetwork::appServiceSubnet.id
    clientAffinityEnabled: false
    keyVaultReferenceIdentity: appServiceIdentity.id
    siteConfig: {
      linuxFxVersion: 'DOCKER|mcr.microsoft.com/appsvc/wordpress-alpine-php:latest'
      vnetRouteAllEnabled: true
      alwaysOn: true
      ipSecurityRestrictions: []
      appSettings: [
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
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=databaseServerPassword)'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://mcr.microsoft.com'
        }
        {
          name: 'PHP_INI_SCAN_DIR'
          value: '/usr/local/etc/php/conf.d:/home/site/ini'
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'true'
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
      ]
    }
  }
}

// custom host name domain bindings
@batchSize(1) // deploy sequentially
resource hostNameBinding 'Microsoft.Web/sites/hostNameBindings@2022-03-01' = [for subDomain in subDomains: {
  name: empty(subDomain) ? domainName : '${subDomain}.${domainName}'
  parent: appService
  properties: {
    siteName: appService.name
    hostNameType: 'Verified'
  }
}]

// app service managed certificate for apex domain
resource managedCertificate 'Microsoft.Web/certificates@2022-03-01' = [for (subDomain, i) in subDomains: {
  name: 'cert-${replace(hostNameBinding[i].name, '.', '-')}'
  location: location
  tags: tags
  properties: {
    serverFarmId: appServicePlan.id
    canonicalName: hostNameBinding[i].name
  }
}]

// role assignment for app service identity to access key vault
module roleAssignment 'roleAssignment.bicep' = {
  name: 'roleAssignment-${workload}'
  scope: resourceGroup(sharedResourceGroupName)
  params: {
    principalId: appServiceIdentity.properties.principalId
    builtInRole: '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
  }
}

// custom domain recoreds
module dnsRecords 'dnsRecords.bicep' = [for (subDomain, i) in subDomains: {
  name: 'dnsRecords-${workload}-${empty(subDomain) ? 'apex' : subDomain}'
  scope: resourceGroup(sharedResourceGroupName)
  params: {
    domainName: domainName
    subDomainName: subDomain
    customDomainVerificationId: appService.properties.customDomainVerificationId
    appServiceIpAddress: appService.properties.inboundIpAddress
    appServiceDefaultHostName: appService.properties.defaultHostName
  }
}]

// enable SNI bindings for custom hostnames
module sniBinding 'sniBinding.bicep' = [for (subDomain, i) in subDomains: {
  name: 'sniBinding-${empty(subDomain) ? 'apex' : subDomain}'
  params: {
    appServiceName: appService.name
    certificateThumbprint: managedCertificate[i].properties.thumbprint
    hostname: hostNameBinding[i].name
  }
}]
