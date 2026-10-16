# Phase 1 · Step 7 — `scripts/deploy-shared.sh`

**Ported from `~/repos/memorywell/scripts/deploy-shared.sh`.** One-time per
subscription: creates `rg-oop-shared` with ACR and App Configuration. Run this
before the first `deploy.sh`.

## Shape

- `#!/usr/bin/env bash`, `set -euo pipefail`, sources `common.sh`.
- `ACTION="${1:-create}"`, rejecting anything but `create` or `what-if` **before
  touching Azure**.
- `az account set --subscription "$SUBSCRIPTION_ID"`.
- Guard on `rg-oop-shared` in `Deleting` state, and fail with the fix. ACR
  purges are slow, so a shared RG can linger in `Deleting` long after teardown;
  a Bicep sub-deploy into that window fails partway through.
- Its own `SHARED_DEPLOYMENT_FILE` (`${TMPDIR:-/tmp}/oop-${BASE_NAME}-shared.deployment`)
  so a shared run never clobbers the environment deployment name — and vice
  versa.
- `az deployment sub "$ACTION" --location "$LOCATION" --name "$SHARED_DEPLOYMENT_NAME"
--template-file infra/shared.bicep --parameters infra/shared.bicepparam`.
- Exit early on `what-if`.
- Read back `registryName` and `loginServer` from
  `az deployment sub show`, then assert `login_server()` equals the returned
  `loginServer`. That assertion is what catches a `.env` `BASE_NAME` that no
  longer matches the deployed registry.
- **No** `curl` health check. Nothing runs in the shared group.
- `chmod +x`.

## Verify

- `bash -n` and `shellcheck --severity=warning scripts/deploy-shared.sh` clean.
- `./scripts/deploy-shared.sh what-if` shows three creations and changes nothing.
- `./scripts/deploy-shared.sh` creates `rg-oop-shared`, and logs the registry
  and login server.
- `az group show --name rg-oop-shared --query properties.provisioningState` is
  `Succeeded`.
- `az acr show -n acroop --query '{sku:sku.name, admin:adminUserEnabled}'` —
  `Basic`, admin `false`.
- Re-running it is idempotent: still `Succeeded`, no error.
- `./scripts/deploy-shared.sh bogus` exits non-zero **before** any `az` call.
