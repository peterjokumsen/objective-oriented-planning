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

Read-only. Per resource group it prints the group's `provisioningState`, then one
`name: state` line per resource, then the latest three group-scope deployments;
afterwards it does the same for subscription-scope deployments filtered to this
project's `oop-dev-` / `oop-shared-` prefixes.

**Exits 0 only when everything is Succeeded** (or nothing is deployed yet), and 1
otherwise — that is the point. A resource list that _looks_ fine is not the same
as a deployment that _succeeded_, so the latest-deployment rows are folded into
the verdict too: a failed last run fails the check even while the live resources
still look healthy.

`--env-only` / `--shared-only` limit it to one side, which is what you want
mid-sequence (after `deploy-shared.sh`, before `deploy.sh`).

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
- `./scripts/check-state.sh --bogus` exits **2** with usage (distinct from the
  other scripts' 1 — a bad flag here is not a failed check).
- `VAL=$(run az account show ... -o tsv)` captures **only** the command's output.
  Both `run` and `init_command_log` log to stderr for exactly this reason; if you
  ever change one to stdout, every `$(...)` capture in the scripts silently gains
  a stray line.
- A failed deployment makes `check-state.sh` exit 1. Prove it rather than
  trusting it: run a `what-if` for a template with an error, or temporarily point
  `SUBSCRIPTION_ID` at a group that does not exist.
