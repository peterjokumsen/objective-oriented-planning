# Phase 1 · Step 2 — Types and per-resource Bicep modules

Write the type file first, then one module per resource. `main.bicep` and
`shared.bicep` are composed in steps 3 and 4, so this step produces modules that
do not yet deploy on their own.

## `infra/_types.bicep`

`EnvironmentType`, `GlobalInputs` (location, baseName, environment,
containerImage), and `ResourceGroupInputs` (global + resourceGroupName + tags).
Both `@export()`ed. A second types file at `infra/modules/_types.bicep` re-exports
`GlobalInputs` and defines `ResourceGroupInputs`, so modules can import without
reaching up two levels for everything.

Keep `environment` typed as `'dev' | 'test' | 'prod'`. It is what gates purge
protection on the vault in `vault.bicep`, and an untyped string makes that
comparison always-true.

## Modules

One file per resource. Each takes `inputs ResourceGroupInputs` unless noted, and
each declares its own outputs — `main.bicep` reads them rather than reaching
inside a resource.

| Module               | Resource / SKU                                        | Outputs                                   |
| -------------------- | ----------------------------------------------------- | ----------------------------------------- |
| `identity.bicep`     | user-assigned managed identity                        | `id`, `principalId`, `clientId`           |
| `monitor.bicep`      | Log Analytics `PerGB2018`                             | `customerId`, `workspaceId`, `apiVersion` |
| `vault.bicep`        | Key Vault standard, family A, RBAC on, soft delete on | `keyVaultName`, `keyVaultUri`             |
| `acr.bicep`          | ACR `Basic`, `adminUserEnabled: false`                | `registryName`, `loginServer`             |
| `appconfig.bicep`    | App Configuration, free tier                          | `storeName`, `endpoint`                   |
| `containerapp.bicep` | managed environment + the `api` app                   | `appName`, `fqdn`                         |
| `acr-pull.bicep`     | **no `inputs`** — see below                           | none                                      |

Points that are easy to get wrong:

- **`acr-pull.bicep` takes `acrName` and `identityPrincipalId` directly, not
  `inputs`**, and targets `resourceGroup` scope at the _shared_ group. A role
  assignment must be scoped to the group holding its target resource, and the
  identity's `principalId` only exists at deploy time — so the grant cannot live
  inside `acr.bicep`, which runs in the shared deployment before the identity
  exists.
- **Two role definition GUIDs, both from memorywell's originals, both easy to
  mistype**: `AcrPull` is `7f951dda-4ed3-4680-a7ca-43fe172d538d`; Key Vault
  Secrets User is `4633458b-17de-408a-b874-0445c86b69e6`. Verify each against
  `az role definition list --name "<role>" --query "[].name"` rather than
  trusting a copy-paste.
- **`purgeProtection` only on prod**: `enablePurgeProtection:
inputs.global.environment == 'prod' ? true : null`. Purge protection on the dev
  vault would block the `--purge-vault` path in step 9.
- **The container app** needs `scale.minReplicas: 0` / `maxReplicas: 1`, external
  ingress on port 8000, `resources` `cpu 0.25` / `memory 0.5Gi`, the user-assigned
  identity, and a `registries` entry using `identity: <identityId>` — not
  `identityName`, and not a registry admin password.
- **Log Analytics reaches the managed environment** through
  `appLogsConfiguration.logAnalyticsConfiguration`, whose shared key comes from
  `listKeys(monitorWorkspaceId, monitorApiVersion).primarySharedKey`. That is why
  `monitor.bicep` outputs both the id and the api version.
- **App Configuration grants no role this phase.** See `_brief.md` § 1 — the
  consumer arrives in Phase 5.

## Verify

- `az bicep build --file infra/_types.bicep --stdout` succeeds on its own.
- Each module file parses: `for f in infra/modules/*.bicep; do az bicep build
--file "$f" --stdout >/dev/null || echo "FAILED $f"; done` prints nothing.
  (A module that imports `_types.bicep` will emit a warning about an unused
  param — a warning is fine, an error is not.)
- `az bicep format --indent-kind Space --indent-size 2 --insert-final-newline
--file <each file>` leaves the files unchanged. The pre-commit hook enforces
  this, so let it run rather than eyeballing it.
