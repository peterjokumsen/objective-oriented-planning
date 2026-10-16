# Phase 1 · Step 4 — `infra/main.bicep`

**Subscription scope**, creating `rg-oop-<env>`. This is the environment
template: everything for one environment lives in this group, so
`az group delete` is the whole teardown.

## Order is the substance of this file

Four things, and the sequence is not stylistic:

1. `resource rg` — the group.
2. `resource acr '...@2025-11-01' existing` at
   `resourceGroup(sharedResourceGroupName)` — referenced, **not** created. The
   shared group must already exist; `deploy.sh` checks for it and fails fast
   pointing at `deploy-shared.sh`.
3. `module identity` at the env RG — deployed first so its `principalId` exists.
4. `module acrPull` at the **shared** RG, then `module platform` at the env RG
   with an explicit `dependsOn: [acrPull]`.

Step 4 depends on step 3 with no output linking them, which is exactly why the
`dependsOn` is written by hand. Without it the first revision starts pulling
before the `AcrPull` grant exists and the app stalls on an unauthorised pull.

## Modules

`platform.bicep` (RG scope) composes `monitor.bicep`, `vault.bicep` and
`containerapp.bicep`, passing `acrLoginServer`, `identityId` and the three
monitor outputs through. It takes `inputs ResourceGroupInputs` plus those five
strings.

`monitor.bicep` must deploy before `containerapp.bicep` — the latter reads
`customerId` and `apiVersion` from the former, which Bicep infers. No output
from `monitor` flows to `vault`, so their relative order is free.

## Params and outputs

Params: `location`, `baseName`, `environment`, `resourceGroupName`,
`containerImage`, `sharedResourceGroupName`, `acrName`.

No `@secure()` params in this phase — nothing secret is passed to Bicep, which is
the point of the managed-identity setup. Do not add one to match memorywell's
Postgres password; it is not needed here.

Outputs: `registryName`, `loginServer`, `appName`, `fqdn`, and pass through
`appConfigStoreName` / `appConfigEndpoint` so `deploy.sh` can read them without
a second `az` call.

## `infra/main.bicepparam`

Same pattern as step 3, plus `containerImage = readEnvironmentVariable('IMAGE',
'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest')`.

That helloworld fallback is not a placeholder to clean up. On a first deploy
there is no `api` repository in the ACR yet, so `deploy.sh` exports the fallback
and the environment deploys with something that runs. The real image is pushed by
`az acr build` in step 8 and the app is repointed at it.

## Verify

- `az bicep build --file infra/main.bicep --stdout` compiles clean, and the same
  for `infra/main.bicepparam`.
- After step 7 has created the shared group:
  `az deployment sub what-if --location westeurope --name oop-dev-whatif
--template-file infra/main.bicep --parameters infra/main.bicepparam`.
  Expect creations for the env group, identity, Log Analytics, Key Vault,
  managed environment, container app, **and the role assignment in the shared
  group**. If the role assignment is absent from the what-if, the
  `acr-pull.bicep` scope is wrong.
- `az bicep format` leaves `infra/main.bicep` unchanged.
