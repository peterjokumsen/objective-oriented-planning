# Phase 1 Brief — Foundation

> **Status: complete and merged (PR #2, 2026-10-16).**
>
> All 11 steps (plus 8a) were implemented, deployed, torn down and redeployed
> live, and every gate item in § 7 was observed. Steps 8, 8a and 9 carry
> corrections from what the live runs revealed; read those before rebuilding. See
> `AGENTS.md` § Build mode.
>
> One `step-x.md` per ordered step in this directory; each step file carries its
> own instructions, stub shapes and verification checks.

## 1. Goal

Stand up the cheapest viable Azure foundation and prove it can be destroyed and
rebuilt on demand. Nothing user-facing ships; the deliverable is infrastructure
that Phase 2 can write a Cosmos container into.

Concretely:

- **Bicep** for the environment (`rg-oop-<env>`) and the shared group
  (`rg-oop-shared`): Log Analytics, Key Vault, Container Apps environment +
  `api` app at `minReplicas: 0`, and — in the shared group — ACR and App
  Configuration.
- **A skeleton API** in `api/` that serves `/health` and `/ready`, containerised
  and pushed to the shared ACR by ACR Tasks.
- **`scripts/teardown.sh`**, ported from the memorywell scripts per
  `AGENTS.md` § Repo rules, plus the `azure/login` + `precheck` steps that arm
  the existing nightly workflow.
- **CI guards removed** as their directories land, so `pytest`, `bicep build`
  and shell checks become real gates rather than permanent no-ops.

### Deliberately not in this phase

Cosmos, the domain model, the tree UI, identity and invites, the coach.
Postgres/Redis/Service Bus/Event Grid/Functions stay closed — see
`docs/PLAN.md` § Deliberately absent.

`web/` is **not** in this phase. `docs/PLAN.md` § Theming previously said
theming lands in Phase 1; that has been corrected to Phase 4, with the
CSS-custom-properties decision recorded there.

App Configuration is **provisioned but not consumed**. No role grant for the
container app identity and no `configProviders` block on the app this phase —
Phase 5 reads keys through them. Provisioning the store now is what makes the
shared group worth having; wiring it is Phase 5's work.

## 2. Concepts practised

- **Bicep at subscription scope**: `main.bicep` and `shared.bicep` create the
  resource groups themselves, so a deploy from a truly absent state needs no
  portal click-ops. Modules scope down to the group they belong in.
- **Shared versus environment resources**: ACR and App Configuration live in
  `rg-oop-shared` and are declared `existing` by the environment template, so
  teardown keeps them by default and a rebuild does not re-push images.
- **Managed identity end to end**: a user-assigned identity per environment,
  attached to the container app, granted `AcrPull` at the _shared_ group's scope
  because the registry lives there. Ordering matters — the grant must exist
  before the first revision tries to pull.
- **Revisions from day one**: `az acr build` pushes both a floating `api:<env>`
  tag and a unique `api:<env>-<timestamp>` tag, and the app is pointed at the
  timestamped one. Re-pushing the same tag string mints no new revision, which
  would make "revisions day one" unprovable.
- **Cost control as infrastructure**: destroy the environment between study
  sessions, and have a nightly job do it when nobody remembers.
- **OIDC from the first workflow**: no client secret anywhere in the repo.

## 3. Prerequisites

- Azure CLI with Bicep installed (`az bicep version` → **must** be `0.48.1`, the
  version pinned in `.github/workflows/ci.yml`; a local/CI mismatch makes the
  format hook and CI's diff disagree). Check it now rather than at step 2.
- Docker, and a local Python 3.11 with `pytest` available.
- `az login` working, one subscription selected, and permission to create
  resource groups at subscription scope.
- `pre-commit install` run once in this checkout.
- A GitHub environment named `azure` and an app registration ready for the
  workflow — step 10 is where those get wired, and `docs/CI_TEARDOWN.md` is
  written to match. Do not run the workflow before that doc is followed.
- Read: `docs/PLAN.md` §§ Decisions, Architecture, Build phases row 1, Cost &
  safety.

## 4. Ordered steps

Do not start a step before the previous one verifies. No Phase 2 work starts
until the review gate in §7 passes.

| Step | File                     | What you build                                              |
| ---- | ------------------------ | ----------------------------------------------------------- |
| 1    | [step-1.md](step-1.md)   | Scaffold empty layout, `.env.example`                       |
| 2    | [step-2.md](step-2.md)   | `infra/_types.bicep` + the per-resource modules             |
| 3    | [step-3.md](step-3.md)   | `infra/shared.bicep` (+param) — shared RG, ACR, App Config  |
| 4    | [step-4.md](step-4.md)   | `infra/main.bicep` (+param) — env RG and platform           |
| 5    | [step-5.md](step-5.md)   | Skeleton API, Dockerfile, tests                             |
| 6    | [step-6.md](step-6.md)   | `scripts/common.sh` — env loading, naming, command logging  |
| 7    | [step-7.md](step-7.md)   | `scripts/deploy-shared.sh`                                  |
| 8    | [step-8.md](step-8.md)   | `scripts/deploy.sh` — image build, revision, health check   |
| 8a   | [step-8a.md](step-8a.md) | `scripts/deploy-all.sh` + `scripts/check-state.sh`          |
| 9    | [step-9.md](step-9.md)   | `scripts/teardown.sh` — cost control                        |
| 10   | [step-10.md](step-10.md) | Arm the nightly workflow, write `docs/CI_TEARDOWN.md`       |
| 11   | [step-11.md](step-11.md) | Remove CI guards, `docs/architecture.md`, full local verify |

## 5. File outline (stubs, not implementations)

```plaintext
infra/_types.bicep                 # EnvironmentType, GlobalInputs, ResourceGroupInputs
infra/shared.bicep                 # sub scope: rg-oop-shared + acr module + appconfig module
infra/shared.bicepparam            # BASE_NAME, LOCATION, SHARED_RG_NAME
infra/main.bicep                   # sub scope: rg-oop-<env> + identity + acrPull + platform,
                                   #   existing refs to acr and appconfig, outputs
infra/main.bicepparam              # BASE_NAME, ENVIRONMENT, LOCATION, RG_NAME, IMAGE,
                                   #   SHARED_RG_NAME, SHARED_ACR_NAME
infra/modules/platform.bicep       # RG scope: monitor + vault + containerapp, ordered
infra/modules/identity.bicep       # user-assigned identity for the api app
infra/modules/monitor.bicep        # Log Analytics, PerGB2018; outputs customerId + apiVersion
infra/modules/vault.bicep          # Key Vault standard + RBAC; grants the identity Secrets User
infra/modules/acr.bicep            # ACR Basic, adminUserEnabled false; no role grants
infra/modules/acr-pull.bicep       # AcrPull at shared-RG scope for an env identity
infra/modules/appconfig.bicep      # App Configuration store, free tier
infra/modules/containerapp.bicep   # managed env (Log Analytics wired) + api app,
                                   #   targetPort 8000, minReplicas 0, maxReplicas 1

api/main.py                        # FastAPI, two routes, nothing else
api/requirements.txt               # fastapi, uvicorn[standard], httpx, pytest — all pinned
api/Dockerfile                     # python:3.11-slim, non-root, EXPOSE 8000
api/.dockerignore                  # keep tests and caches out of the build context
api/tests/test_main.py             # /health and /ready assertions via TestClient

scripts/common.sh                  # .env loader, RG/ACR/vault naming, DEPLOYMENT_NAME +
                                   #   IMAGE_TAG; sources the two `_` helpers below
scripts/_log.sh                    # logging backends (_log-local/_log-ghactions),
                                   #   log_vars, init_command_log/log_cmd/run
scripts/_azure.sh                  # subscription_name, group_exists, vault_* probes,
                                   #   fetch_deployment_outputs, run_deployment
scripts/validate-bicep.sh          # compiles infra/**/*.bicep + *.bicepparam
                                   #   with --stdout into build/bicep
scripts/check-logging.sh           # offline self-check: every printer, both
                                   #   backends, console + logs + run summary
scripts/deploy-all.sh              # shared then environment; action passed through
scripts/check-state.sh             # read-only provisioning check over every
                                   #   rg-<base>* group; exits 0/1, or 0/1/2
                                   #   for --rg <name> (+ --summary)
scripts/deploy-shared.sh           # sub deploy of shared.bicep; create|what-if;
                                   #   polls the deployment state until Succeeded
scripts/deploy.sh                  # sub deploy, acr build, containerapp update, /health
                                   #   poll; self-heals a missing shared group on create
scripts/teardown.sh                # RG delete, optional --purge-vault, --shared; also
                                   #   --precheck and --verify for the workflow; idempotent
logs/                              # per-run command logs (git-ignored, created at run time)

docs/architecture.md               # deployed topology + the occurrence split threshold
docs/CI_TEARDOWN.md                # one-time Azure + GitHub setup for the workflow
docs/phase-1/                      # this brief and the step files
```

`api/pyproject.toml` is deliberately absent: Ruff config already lives in the
root `pyproject.toml` and the hooks run from the repo root, so a second copy
would be a second place for the formatting rules to drift.

## 6. Verification (per step)

Each step file carries its own checks. Run these locally before every push:

- `pytest -q` **from `api/`** — matching CI's `working-directory`. The tests
  insert `api/` onto `sys.path` themselves, so they also pass from the repo root;
  running from `api/` locally is what makes a local pass comparable to CI's.
- `az bicep build --file infra/main.bicep --stdout`, the same for
  `shared.bicep`, and a format check via `az bicep format --indent-kind Space
--indent-size 2 --insert-final-newline --file <f>`.
- `bash -n scripts/*.sh` and `shellcheck --severity=warning scripts/*.sh`.
- `pre-commit run --all-files` is CI's job; locally the hooks run on staged
  files at commit time.

## 7. Review gate (demo before Phase 2) — PASSED

All seven observed (2026-10-16); see § 7a for what only a live run found.

1. `az containerapp show` — FQDN — and the output of
   `curl -sSf https://<fqdn>/health`.
2. `az containerapp revision list --output table` — **two or more revisions**,
   the latest active. One revision means the timestamped-tag rule is not working.
3. The `scripts/deploy.sh` run log for the revision-mining step, including the
   `az acr build` tag list.
4. The `scripts/teardown.sh --purge-vault` run log, followed by a **fresh
   `deploy.sh` from an absent resource group** — two teardown/redeploy cycles
   if you have the appetite, one is the minimum. This is the real proof that
   the vault was purged and that no portal click-ops are involved.
5. `az group list --query '[].name' -o tsv` after teardown: `rg-oop-shared`
   present, `rg-oop-dev` gone.
6. One nightly workflow run from the Actions tab — the `workflow_dispatch`
   pre-check path when the RG is already absent, showing it skipped every
   destructive step and cost nothing.
7. `git status --short` — only intended files, no `.env`, no `infra/*.json`
   build output.

The agent sanity-checks these before issuing the Phase 2 brief.

## 7a. What only a live run found

Three defects were invisible to local checks and only appeared once CI and the
nightly workflow actually ran. They are recorded because the pattern recurs:

| Found by             | Defect                                                                                                                                                                                                                                    | Fix                                                                                                                                                                      |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| First live deploy    | Misdiagnosed a lone revision as single-revision mode and added `revisionMode: 'Multiple'` — which **failed the whole deployment** (BCP037)                                                                                                | Reverted; revisions already work. Do not "fix" this again                                                                                                                |
| First teardown       | `--verify` budgeted ~5 min; the managed environment takes ~30, so it reported a **false failure**                                                                                                                                         | ~40 min poll, workflow `timeout-minutes: 60`                                                                                                                             |
| **CI (PR #2)**       | `bicep build` **rejects** `.bicepparam` ("must use the .bicep extension"), so extending the build loop broke the IaC job — while `bicep format` accepts it                                                                                | Build loop stays `.bicep`; format check covers both                                                                                                                      |
| **Nightly dispatch** | The workflow injected `AZURE_SUBSCRIPTION_ID` but `common.sh` requires `SUBSCRIPTION_ID`, so **every** run died at the pre-check                                                                                                          | Inject the `.env` name; `azure/login` reads the secret via `with:`                                                                                                       |
| **Nightly dispatch** | The purge step skipped the Key Vault: 12 s after the async RG delete the vault was _neither live nor soft-deleted_, which the "nothing to purge" branch read as already-purged. The vault stayed soft-deleted and `--verify` failed on it | Skip that branch only when the vault was **not live when the run started** (`VAULT_WAS_LIVE`, probed before the delete); vault wait 5 → 20 min, workflow timeout 60 → 90 |

The last two are the argument for both gates existing: the build-only checks
passed locally, and only CI and a real dispatch found the rest. The vault bug is
worth remembering for two reasons. It was invisible to the repeat-run test that
_motivated_ the skip branch — it only appears on the first teardown after a
deploy. And the obvious first fix ("skip only if we didn't delete the group this
run") was also wrong: on a re-run while the group is still draining, that blocks
the skip and then waits 20 minutes for a vault that was already purged. The
question that actually separates the two cases is whether the vault was live when
the run _started_, which is why the probe happens before the delete.

**Cost reminder.** The environment RG is destroyed between study sessions via
`scripts/teardown.sh`; the nightly workflow does it when you forget. While
running, expect ≈ ACR Basic plus near-zero consumption. `rg-oop-shared` is
kept deliberately — it is the only always-on cost and rebuilding it means
re-pushing every image.

**Gate assumption.** This phase assumes a live deploy. `scripts/teardown.sh` is
cost-control infrastructure; an unrun teardown script is an assumption, and a
nightly job that has never executed is a worse one than no job at all.
