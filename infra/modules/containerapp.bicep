import { ResourceGroupInputs } from './_types.bicep'

param inputs ResourceGroupInputs
param acrLoginServer string
param identityId string
param monitorCustomerId string
param monitorWorkspaceId string
param monitorApiVersion string

// Log Analytics is wired into the managed environment from day one, so container
// logs flow before there is anything to debug. It is ingest-billed and the app
// scales to zero, so an idle environment costs nothing.
resource managedEnvironment 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: 'managed-env-${inputs.global.baseName}-${inputs.global.environment}'
  location: inputs.global.location
  tags: inputs.tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: monitorCustomerId
        sharedKey: listKeys(monitorWorkspaceId, monitorApiVersion).primarySharedKey
      }
    }
  }
}

resource containerApp 'Microsoft.App/containerApps@2025-07-01' = {
  name: 'ca-${inputs.global.baseName}-${inputs.global.environment}'
  location: inputs.global.location
  tags: inputs.tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: managedEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8000
        transport: 'Auto'
      }
      registries: [
        {
          server: acrLoginServer
          // identity (the resource id), not identityName: the app pulls with the
          // user-assigned identity granted AcrPull by acr-pull.bicep. No admin
          // password is configured anywhere.
          identity: identityId
        }
      ]
    }
    template: {
      scale: {
        // minReplicas 0 is the cost control. Nothing runs between study sessions.
        minReplicas: 0
        maxReplicas: 1
      }
      containers: [
        {
          name: 'ca-c-${inputs.global.baseName}-${inputs.global.environment}'
          image: inputs.global.containerImage
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
    }
  }
}

output fqdn string = containerApp.properties.configuration.ingress.fqdn
output appName string = containerApp.name
output containerAppId string = containerApp.id
