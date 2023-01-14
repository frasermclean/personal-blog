targetScope = 'resourceGroup'

//@description('The ID of the resource to assign the role to.')
//param resourceId string

@description('The principal ID of the user or service principal to assign the role to.')
param principalId string

@description('The Azure AD built-in role to assign to the service principal. See https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles for a list of built-in role definitions.')
param builtInRole string

// get reference to existing key vault
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: 'kv-frasermclean-shared'
}

// lookup built-in role definition from subscription
resource roleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: builtInRole
  scope: subscription()
}

// assign role to key vault
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, principalId, roleDefinition.id)

  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinition.id
    description: 'Allow application to access secrets in key vault'
  }
}
