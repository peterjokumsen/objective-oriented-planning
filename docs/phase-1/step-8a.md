# Phase 1 · Step 8a — `deploy-all.sh` and `check-state.sh`

Two convenience/observability scripts ported from
`~/repos/memorywell/scripts/`, added after the first live deploys showed the
gap. Neither is required for a deploy to work; both exist because "did that
actually work?" was the recurring question.

## `scripts/deploy-all.sh`

Shared resources first, then the environment, action passed through to both
(`./deploy-all.sh what-if` analyses both). Fails fast: the environment step never
runs if the shared step fails.

Note this is now genuinely optional rather than a shortcut, because `deploy.sh`
self-heals a missing shared group on `create` (step 8). Its value is a clean
two-phase log you can read top to bottom, not correctness.

## `scripts/check-state.sh`

Read-only. It runs every probe first (each `step`/`+` line goes to stderr), then
prints one consolidated report: per resource group the group's `provisioningState`,
then one `name: state` line per resource, then the latest three group-scope
deployments; afterwards it does the same for subscription-scope deployments
filtered to that group's name prefix (`oop-dev-`, `oop-shared-`, …). Lines are
colour-coded by state locally and turned into GitHub Actions annotations in CI
(`scripts/_log.sh` picks the backend).

**Exits 0 only when everything is Succeeded** (or nothing is deployed yet), and 1
otherwise — that is the point. A resource list that _looks_ fine is not the same
as a deployment that _succeeded_, so the latest-deployment rows are folded into
the verdict too: a failed last run fails the check even while the live resources
still look healthy.

With no `--rg` the scope is **every resource group belonging to `$BASE_NAME`**,
discovered from the subscription with `az group list` rather than assumed from
`$ENVIRONMENT`. That matters the moment a second environment exists: a report
built from `rg-<base>-$ENVIRONMENT` plus `rg-<base>-shared` silently omits a
`staging` group that is burning money. `--env-only` / `--shared-only` narrow it
back to the two names `common.sh` derives, which is what you want mid-sequence
(after `deploy-shared.sh`, before `deploy.sh`).

A failed listing and a successful-but-empty listing are kept apart on purpose.
A failed one falls back to the derived names **with a warning**, because an
outage must not be presented as "everything is deleted"; an empty one reports
the derived names as absent, which is the true answer.

`--rg <name>` is a fourth mode, added when `teardown.sh --verify` grew progress
reporting: it reports a single resource group — its provisioning state and its
resources' states, nothing else — with no command traces and no log files, and
answers in its **exit code** so a caller need not parse the report: **0** absent,
**1** present but something is not Succeeded, **2** present and everything
Succeeded. `teardown.sh --verify` prints that verdict every 10 minutes while it
waits for the group to drain. A usage error exits **64**, which collides with
none of them.

An empty `--rg=` (the flag with no value) is treated as a typo rather than an
empty scope: it warns and falls back to the full scope, because silently
reporting nothing is the worst available answer. `--rg` with no following
argument at all is still a usage error (**64**).

`--summary` (with `--rg`) appends the same facts to the workflow run summary as
a markdown table, built from the collected values rather than scraped from the
console output, so it stays correct whichever backend is printing. A 30-minute
teardown is a scroll; the summary is a table. Outside a workflow run there is no
summary file and it is a no-op.

Two things to know about the output, both verified rather than assumed:

- **Most resources report `n/a`.** `az resource show --query provisioningState`
  returns nothing for managed identities, Log Analytics, Container Apps and the
  ACR — the field simply does not exist at the top level for those types.
  `n/a` resources are excluded from the verdict. In practice the _deployment_
  rows carry the signal, which is why they are not optional.
- **It is generic.** `az resource list` means a new Bicep module shows up here
  with no change to this script.

## Verify

- `bash -n` and shellcheck clean.
- `./scripts/check-state.sh` exits 0 and reports "everything Succeeded" against
  the deployed environment.
- `./scripts/check-state.sh --shared-only` and `--env-only` each check one side.
- `./scripts/check-state.sh --rg rg-oop-dev` exits **2** against a deployed
  environment, `--rg rg-oop-nonexistent` exits **0**, and `--rg` with no name
  exits **64**.
- `./scripts/check-state.sh --bogus` exits **64** with usage (distinct from the
  other scripts' 1 — a bad flag here is not a failed check).
- `./scripts/check-state.sh --summary` without `--rg` exits **64**: the summary
  block only exists for the single-group report.
- `./scripts/check-logging.sh` passes every assertion (it is a CI gate).
- `VAL=$(run az account show ... -o tsv)` captures **only** the command's output.
  Both `run` and `init_command_log` log to stderr for exactly this reason; if you
  ever change one to stdout, every `$(...)` capture in the scripts silently gains
  a stray line.
- A failed deployment makes `check-state.sh` exit 1. Prove it rather than
  trusting it: run a `what-if` for a template with an error, or temporarily point
  `SUBSCRIPTION_ID` at a group that does not exist.
