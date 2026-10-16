import { GlobalInputs, EnvironmentType } from './_types.bicep'

// Everything for one environment. Scoped to the subscription so it creates the
// resource group itself: a deploy from a completely absent state needs no
// portal click-ops, which is what makes the teardown/redeploy cycle in the
// Phase 1 gate meaningful.
targetScope = 'subscription'

param location string
param baseName string
param environment EnvironmentType
param resourceGroupName string
param containerImage string
param sharedResourceGroupName string
param acrName string

var globalInputs GlobalInputs = {
  location: location
  baseName: baseName
  environment: environment
  containerImage: containerImage
}

var tags = {
  Environment: globalInputs.environment
  BaseName: globalInputs.baseName
}

var inputs = {
  global: globalInputs
  resourceGroupName: resourceGroupName
  tags: tags
}

resource rg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: globalInputs.location
  tags: tags
}

// The ACR and the App Configuration store live in the shared group and were
// created by the shared deployment. Referenced, not created: one registry and one
// config store serve every environment. deploy.sh fails fast if they are missing,
// rather than letting this fail partway through after creating the env group.
resource acr 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: acrName
  scope: resourceGroup(sharedResourceGroupName)
}

resource appConfig 'Microsoft.AppConfiguration/configurationStores@2024-05-01' existing = {
  name: toLower(replace('appconfig-${baseName}', '-', ''))
  scope: resourceGroup(sharedResourceGroupName)
}

// Deployed before platform so the AcrPull grant below has a principalId to bind.
module identity './modules/identity.bicep' = {
  name: '${deployment().name}-identity'
  scope: rg
  params: {
    inputs: inputs
  }
}

// AcrPull, at the shared group's scope because that is where the registry is.
// Without this the first revision stalls on an unauthorised image pull.
module acrPull './modules/acr-pull.bicep' = {
  name: '${deployment().name}-acr-pull'
  scope: resourceGroup(sharedResourceGroupName)
  params: {
    acrName: acr.name
    identityPrincipalId: identity.outputs.principalId
  }
}

module platform './modules/platform.bicep' = {
  name: '${deployment().name}-platform'
  scope: rg
  params: {
    inputs: inputs
    acrLoginServer: acr.properties.loginServer
    identityId: identity.outputs.id
    identityPrincipalId: identity.outputs.principalId
  }
  // Nothing in platform's outputs depends on acrPull, so Bicep cannot infer this
  // ordering. Written by hand: the app must not start pulling before the grant
  // exists.
  dependsOn: [
    acrPull
  ]
}

output registryName string = acr.name
output loginServer string = acr.properties.loginServer
output appName string = platform.outputs.appName
output fqdn string = platform.outputs.fqdn
output keyVaultName string = platform.outputs.keyVaultName
output appConfigStoreName string = appConfig.name
output appConfigEndpoint string = appConfig.properties.endpoint
