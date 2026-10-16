import { ResourceGroupInputs } from './_types.bicep'

// Everything belonging to one environment, scoped to that environment's resource
// group. `az group delete` on that group is the whole teardown.
targetScope = 'resourceGroup'

param inputs ResourceGroupInputs
param acrLoginServer string
param identityId string
param identityPrincipalId string

module monitoring 'monitor.bicep' = {
  name: '${deployment().name}-monitoring'
  params: {
    inputs: inputs
  }
}

module keyVault 'vault.bicep' = {
  name: '${deployment().name}-keyvault'
  params: {
    inputs: inputs
    identityPrincipalId: identityPrincipalId
  }
}

// Depends on monitoring via its outputs: the managed environment needs the
// workspace's customerId and apiVersion to list its shared key.
module containerApp 'containerapp.bicep' = {
  name: '${deployment().name}-containerapp'
  params: {
    inputs: inputs
    acrLoginServer: acrLoginServer
    identityId: identityId
    monitorCustomerId: monitoring.outputs.customerId
    monitorWorkspaceId: monitoring.outputs.workspaceId
    monitorApiVersion: monitoring.outputs.apiVersion
  }
}

output appName string = containerApp.outputs.appName
output fqdn string = containerApp.outputs.fqdn
output keyVaultName string = keyVault.outputs.keyVaultName
