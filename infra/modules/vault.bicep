import { ResourceGroupInputs } from './_types.bicep'

param inputs ResourceGroupInputs
param identityPrincipalId string

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${inputs.global.baseName}-${inputs.global.environment}'
  location: inputs.global.location
  tags: inputs.tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    tenantId: subscription().tenantId
    enableSoftDelete: true
    // Purge protection is off outside prod: scripts/teardown.sh --purge-vault
    // purges the soft-deleted vault so the next same-name deploy succeeds, and
    // purge protection would refuse exactly that.
    enablePurgeProtection: inputs.global.environment == 'prod' ? true : null
  }
}

// Key Vault Secrets User: the api app's identity reads secrets injected as env
// vars. No secrets exist yet in Phase 1; the grant lands with the first one.
var keyVaultSecretsRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
resource secretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, identityPrincipalId, keyVaultSecretsRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsRoleId)
    principalId: identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri
output keyVaultName string = keyVault.name
