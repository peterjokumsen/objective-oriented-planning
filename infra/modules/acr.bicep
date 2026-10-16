param location string
param registryName string
param tags object

resource acr 'Microsoft.ContainerRegistry/registries@2025-11-01' = {
  name: registryName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

// No role grants in this module. The registry is deployed once by the shared
// deployment, before any environment identity exists; the AcrPull grant lives in
// acr-pull.bicep, deployed per environment at the shared group's scope.
output registryName string = acr.name
output loginServer string = acr.properties.loginServer
