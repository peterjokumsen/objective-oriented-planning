// AcrPull grant for an environment's identity, deployed into the shared resource
// group because a role assignment must be scoped to the group holding its target
// resource -- and the registry lives in rg-oop-shared, not in the environment's
// group.
//
// Takes the identity's principalId directly rather than ResourceGroupInputs: the
// identity does not exist yet when the shared deployment runs, so its principalId
// is only available at environment-deploy time.
targetScope = 'resourceGroup'

param acrName string
param identityPrincipalId string

resource acr 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: acrName
}

var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull
resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, identityPrincipalId, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}
