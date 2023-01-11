targetScope = 'resourceGroup'

@description('Name of the workload / application')
param workload string

@description('Domain name for the WordPress site')
param domainName string

@description('Name of the app service')
param appServiceName string

@description('Name of the storage account')
param storageAccountName string

@description('Name of the storage container')
param storageContainerName string

// azure front door profile
resource profile 'Microsoft.Cdn/profiles@2021-06-01' existing = {
  name: 'afd-frasermclean-shared'

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

  // endpoint
  resource endpoint 'afdEndpoints' = {
    name: workload
    location: 'global'
    properties: {
      enabledState: 'Enabled'
    }

    // default route
    resource route 'routes' = {
      name: 'route-default'
      dependsOn: [
        appServicesOriginGroup::appServiceOrigin // ensure origin is created before route
      ]
      properties: {
        forwardingProtocol: 'HttpsOnly'
        linkToDefaultDomain: 'Enabled'
        httpsRedirect: 'Enabled'
        originGroup: {
          id: appServicesOriginGroup.id
        }
        customDomains: [
          { id: apexCustomDomain.id }
          { id: wwwCustomDomain.id }
        ]
        ruleSets: [
          { id: ruleSet.id }
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

  // origin group for app services
  resource appServicesOriginGroup 'originGroups' = {
    name: 'og-blog-appService'
    properties: {
      loadBalancingSettings: {
        sampleSize: 4
        successfulSamplesRequired: 3
        additionalLatencyInMilliseconds: 50
      }
      healthProbeSettings: {
        probePath: '/'
        probeRequestType: 'HEAD'
        probeProtocol: 'Http'
        probeIntervalInSeconds: 100
      }
    }

    // origin for app service
    resource appServiceOrigin 'origins' = {
      name: 'origin-${appServiceName}'
      properties: {
        hostName: '${appServiceName}.azurewebsites.net'
        httpPort: 80
        httpsPort: 443
        enabledState: 'Enabled'
        originHostHeader: '${appServiceName}.azurewebsites.net'
        priority: 1
        weight: 1000
      }
    }
  }

  // origin group for storage accounts
  resource storageAccountsOriginGroup 'originGroups' = {
    name: 'og-blog-storage'
    properties: {
      loadBalancingSettings: {
        sampleSize: 4
        successfulSamplesRequired: 3
        additionalLatencyInMilliseconds: 50
      }
    }

    // origin for storage account
    resource storageAccountOrigin 'origins' = {
      name: 'origin-${storageAccountName}'
      properties: {
        hostName: '${storageAccountName}.blob.${environment().suffixes.storage}'
        httpPort: 80
        httpsPort: 443
        enabledState: 'Enabled'
        originHostHeader: '${storageAccountName}.blob.${environment().suffixes.storage}'
        priority: 1
        weight: 1000
      }
    }
  }

  // rule set
  resource ruleSet 'ruleSets' = {
    name: 'blogRuleSet'

    // rule to override storage container requests
    resource storageContainerRule 'rules' = {
      name: 'storageContainerOverride'
      properties: {
        order: 1
        matchProcessingBehavior: 'Stop'
        conditions: [
          {
            name: 'UrlPath'
            parameters: {
              typeName: 'DeliveryRuleUrlPathMatchConditionParameters'
              operator: 'BeginsWith'
              negateCondition: false
              matchValues: [ '${storageContainerName}/wp-content/uploads/' ]
              transforms: [ 'Lowercase' ]
            }
          }
        ]
        actions: [
          {
            name: 'RouteConfigurationOverride'
            parameters: {
              typeName: 'DeliveryRuleRouteConfigurationOverrideActionParameters'
              cacheConfiguration: {
                isCompressionEnabled: 'Enabled'
                queryStringCachingBehavior: 'UseQueryString'
                cacheBehavior: 'OverrideAlways'
                cacheDuration: '3.00:00:00'
              }
              originGroupOverride: {
                forwardingProtocol: 'MatchRequest'
                originGroup: {
                  id: storageAccountsOriginGroup.id
                }
              }
            }
          }
        ]
      }
    }

    // rule to cache static content
    resource cacheStaticContentRule 'rules' = {
      name: 'cacheStaticContent'
      properties: {
        order: 2
        matchProcessingBehavior: 'Stop'
        conditions: [
          {
            name: 'UrlPath'
            parameters: {
              typeName: 'DeliveryRuleUrlPathMatchConditionParameters'
              operator: 'BeginsWith'
              negateCondition: false
              matchValues: [
                'wp-includes/'
                'wp-content/themes/'
              ]
              transforms: [ 'Lowercase' ]
            }
          }
          {
            name: 'UrlFileExtension'
            parameters: {
              typeName: 'DeliveryRuleUrlFileExtensionMatchConditionParameters'
              operator: 'Equal'
              negateCondition: false
              matchValues: [
                'css'
                'js'
                'gif'
                'png'
                'jpg'
                'ico'
                'ttf'
                'otf'
                'woff'
                'woff2'
              ]
              transforms: [
                'Lowercase'
              ]
            }
          }
        ]
        actions: [
          {
            name: 'RouteConfigurationOverride'
            parameters: {
              typeName: 'DeliveryRuleRouteConfigurationOverrideActionParameters'
              cacheConfiguration: {
                isCompressionEnabled: 'Enabled'
                queryStringCachingBehavior: 'UseQueryString'
                cacheBehavior: 'OverrideAlways'
                cacheDuration: '3.00:00:00'
              }
            }
          }
        ]
      }
    }
  }
}

// dns zone (existing)
resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' existing = {
  name: domainName

  // azure front door custom domain validation for apex domain
  resource apexCustomDomainAuthorizationRecord 'TXT' = {
    name: '_dnsauth'
    properties: {
      TTL: 3600
      TXTRecords: [
        { value: [ profile::apexCustomDomain.properties.validationProperties.validationToken ] }
      ]
    }
  }

  // A record for apex domain
  resource apexCustomDomainARecord 'A' = {
    name: '@'
    properties: {
      TTL: 3600
      targetResource: {
        id: profile::endpoint.id
      }
    }
  }

  // azure front door custom domain validation for www subdomain
  resource wwwCustomDomainAuthorizationRecord 'TXT' = {
    name: '_dnsauth.www'
    properties: {
      TTL: 3600
      TXTRecords: [
        { value: [ profile::wwwCustomDomain.properties.validationProperties.validationToken ] }
      ]
    }
  }

  // CNAME record for www subdomain
  resource wwwCustomDomainCnameRecord 'CNAME' = {
    name: 'www'
    properties: {
      TTL: 3600
      CNAMERecord: {
        cname: profile::endpoint.properties.hostName
      }
    }
  }
}

output frontDoorId string = profile.properties.frontDoorId
output endpointHostName string = profile::endpoint.properties.hostName
output endpointCustomDomain string = profile::apexCustomDomain.properties.hostName
