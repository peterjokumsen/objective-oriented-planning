// App Configuration store. Provisioned in the shared group alongside the ACR so
// dev and prod read the same store, namespaced by key prefix (`dev.*` / `prod.*`).
//
// Nothing reads it yet. Phase 5's config.py consumes it, and that phase adds the
// App Configuration Reader grant for the container app's identity plus the
// container app's configProviders block -- both deliberately absent here.
param location string
param storeName string
param tags object

resource appConfig 'Microsoft.AppConfiguration/configurationStores@2024-05-01' = {
  name: storeName
  location: location
  tags: tags
  sku: {
    name: 'free'
  }
}

output storeName string = appConfig.name
output endpoint string = appConfig.properties.endpoint
