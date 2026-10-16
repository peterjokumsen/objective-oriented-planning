import { ResourceGroupInputs } from './_types.bicep'

param inputs ResourceGroupInputs

resource monitoring 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-${inputs.global.baseName}-${inputs.global.environment}'
  location: inputs.global.location
  tags: inputs.tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

output workspaceId string = monitoring.id
output customerId string = monitoring.properties.customerId
output apiVersion string = monitoring.apiVersion
