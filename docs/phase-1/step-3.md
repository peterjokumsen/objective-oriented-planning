# Phase 1 · Step 3 — `infra/shared.bicep`

**Subscription scope.** The shared resource group `rg-oop-shared` is created
_by this template_, not assumed. That is what lets `deploy-shared.sh` run from a
completely absent state with no portal click-ops.

## Shape

- `targetScope = 'subscription'`
- Params: `location`, `baseName`, `sharedResourceGroupName`
- `var tags = { BaseName: baseName }` — the shared group has no environment, so
  no `Environment` tag here
- `var registryName = toLower(replace('acr${baseName}', '-', ''))` → `acroop`.
  ACR names are globally unique, lowercase, alphanumeric only.
- `resource sharedRg 'Microsoft.Resources/resourceGroups@2025-04-01'` with that
  name, the location, the tags.
- Two modules scoped to `sharedRg`: `acr.bicep` and `appconfig.bicep`.
- Outputs: `registryName`, `loginServer`, plus `storeName` and `appConfigEndpoint`
  from the App Configuration module.

No role assignments in this template. The environment's identity does not exist
yet when this runs.

## `infra/shared.bicepparam`

```bicep
using './shared.bicep'
param baseName = readEnvironmentVariable('BASE_NAME', 'oop')
param location = readEnvironmentVariable('LOCATION', 'westeurope')
param sharedResourceGroupName = readEnvironmentVariable('SHARED_RG_NAME', '')
```

Note the `''` default on the group name: `common.sh` computes it from `BASE_NAME`
in step 6. The empty default is deliberate — it fails loudly at deploy time
rather than silently creating `rg--shared`.

## Verify

- `az bicep build --file infra/shared.bicep --stdout` compiles clean.
- `az deployment sub what-if --location westeurope --name oop-shared-whatif
--template-file infra/shared.bicep --parameters infra/shared.bicepparam`
  shows exactly three creations: the resource group, the registry, the App
  Configuration store. **Read the what-if.** An `existing` marker or a missing
  `Microsoft.AppConfiguration` type means something is wrong before you spend
  money.
