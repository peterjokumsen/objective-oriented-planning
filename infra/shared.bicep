// Shared resources for every environment: the ACR and the App Configuration
// store, both in rg-oop-shared.
//
// Deployed once by scripts/deploy-shared.sh. Environment deployments reference
// what is here as `existing` rather than owning it, so tearing down an
// environment does not force a re-push of every image.
targetScope = 'subscription'

param location string
param baseName string
param sharedResourceGroupName string

var tags = {
  BaseName: baseName
}

// ACR names are globally unique, lowercase and alphanumeric-only.
var registryName = toLower(replace('acr${baseName}', '-', ''))

// App Configuration store names are globally unique too.
var configStoreName = toLower(replace('appconfig-${baseName}', '-', ''))

resource sharedRg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: sharedResourceGroupName
  location: location
  tags: tags
}

module acr './modules/acr.bicep' = {
  name: '${deployment().name}-acr'
  scope: sharedRg
  params: {
    location: location
    registryName: registryName
    tags: tags
  }
}

module appConfig './modules/appconfig.bicep' = {
  name: '${deployment().name}-appconfig'
  scope: sharedRg
  params: {
    location: location
    storeName: configStoreName
    tags: tags
  }
}

output registryName string = acr.outputs.registryName
output loginServer string = acr.outputs.loginServer
output appConfigStoreName string = appConfig.outputs.storeName
output appConfigEndpoint string = appConfig.outputs.endpoint
