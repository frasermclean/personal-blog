
@description('Name of the app service')
param appServiceName string

@description('Hostname to bind to')
param hostname string

@description('Certificate\'s thumbprint ID')
param certificateThumbprint string

resource hostNameBinding 'Microsoft.Web/sites/hostNameBindings@2022-03-01' = {
  name: '${appServiceName}/${hostname}'
  properties: {
    sslState: 'SniEnabled'
    thumbprint: certificateThumbprint
  }
}
