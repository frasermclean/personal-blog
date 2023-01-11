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
resource afdProfile 'Microsoft.Cdn/profiles@2021-06-01' existing = {
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
        { value: [ afdProfile::apexCustomDomain.properties.validationProperties.validationToken ] }
      ]
    }
  }

  // A record for apex domain
  resource apexCustomDomainARecord 'A' = {
    name: '@'
    properties: {
      TTL: 3600
      targetResource: {
        id: afdProfile::endpoint.id
      }
    }
  }

  // azure front door custom domain validation for www subdomain
  resource wwwCustomDomainAuthorizationRecord 'TXT' = {
    name: '_dnsauth.www'
    properties: {
      TTL: 3600
      TXTRecords: [
        { value: [ afdProfile::wwwCustomDomain.properties.validationProperties.validationToken ] }
      ]
    }
  }

  // CNAME record for www subdomain
  resource wwwCustomDomainCnameRecord 'CNAME' = {
    name: 'www'
    properties: {
      TTL: 3600
      CNAMERecord: {
        cname: afdProfile::endpoint.properties.hostName
      }
    }
  }
}

output frontDoorId string = afdProfile.properties.frontDoorId
output endpointHostName string = afdProfile::endpoint.properties.hostName
output endpointCustomDomain string = afdProfile::apexCustomDomain.properties.hostName
