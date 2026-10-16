# Architecture — as built

The **source of truth** is [`PLAN.md`](PLAN.md). This file is the as-built view
of Phase 1: what actually exists, which group holds what, and the one threshold
that `PLAN.md` deliberately deferred to here.

## Resource topology

### `rg-oop-shared` — shared across environments

Created once by [`scripts/deploy-shared.sh`](../scripts/deploy-shared.sh),
referenced as `existing` by every environment deployment.

| Resource       | Name           | SKU     | Why shared                                                                                                           |
| -------------- | -------------- | ------- | -------------------------------------------------------------------------------------------------------------------- |
| Container Reg. | `acroop`       | `Basic` | One registry serves every environment; rebuilding it means re-pushing every image                                    |
| App Config     | `appconfigoop` | `free`  | One store, keys namespaced `dev.*` / `prod.*`; one store rather than one per group is what makes it free-tier-viable |

Kept by `teardown.sh` unless `--shared` is passed. It is the only always-on cost.

### `rg-oop-<env>` — one per environment

Created by [`scripts/deploy.sh`](../scripts/deploy.sh). **`az group delete` on
this group is the entire teardown** — everything below is in it by construction.

| Resource           | Name                    | Notes                                                                                                            |
| ------------------ | ----------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Managed identity   | `identity-oop-<env>`    | User-assigned, attached to the container app                                                                     |
| Log Analytics      | `log-oop-<env>`         | `PerGB2018`, ingest-billed, ~$0 while idle                                                                       |
| Key Vault          | `kv-oop-<env>`          | Standard, RBAC on, soft delete on; purge protection **off** outside prod so `teardown.sh --purge-vault` can work |
| Container Apps env | `managed-env-oop-<env>` | Log Analytics wired in from day one                                                                              |
| Container App      | `ca-oop-<env>`          | Consumption, `minReplicas: 0`, ingress on 8000                                                                   |

## Identities and grants

| Identity             | Scope         | Grant                  | Why                                                                                                                                                             |
| -------------------- | ------------- | ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `identity-oop-<env>` | env RG        | Key Vault Secrets User | Reads secrets injected as env vars. None exist yet; the grant lands with the first one                                                                          |
| `identity-oop-<env>` | **shared RG** | `AcrPull`              | The registry lives in the shared group, so the assignment is scoped there. Deployed **before** `platform`, or the first revision stalls on an unauthorised pull |

The container app pulls with this identity — `registries[].identity`, not a
registry admin password. The registry has `adminUserEnabled: false`.

Deliberately **not** granted yet: App Configuration Reader on `appconfigoop`.
Nothing reads the store until Phase 5, which adds both that grant and the
container app's `configProviders` block.

## Occurrence partitioning and the split threshold

Occurrences share the `planId` partition with everything else, so loading one
repeatable's log is a cross-partition scan filtered in process, not a point read.
That is the right trade at v1: one container, one Bicep resource, one read path.

Recorded here so the decision is deliberate rather than discovered later:

> **Split when a single repeatable exceeds ~5,000 occurrences, or a plan exceeds
> ~50,000 objectives total.** At that point add a second container with partition
> key `/objectiveId` and move `occurrence` into it.

Revisit if the app is ever used for more than a handful of concurrent plans.

## Conventions worth keeping

- **Names derive from `BASE_NAME`.** `rg-oop-<env>`, `rg-oop-shared`, `acroop`,
  `kv-oop-<env>`, `ca-oop-<env>`, all computed in `scripts/common.sh`. The plan
  names the groups explicitly, so `BASE_NAME=oop` is not a free choice.
- **Deployment names are unique per run** (`oop-dev-YYYYmmdd-HHMMSS`), because
  `az deployment sub create` names must be unique or history is overwritten.
- **Image tags carry that timestamp**, which is what mints a new Container Apps
  revision on each deploy. Re-pushing the floating `api:<env>` tag alone would
  change nothing, because Container Apps reacts to the image _string_.
