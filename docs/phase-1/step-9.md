# Phase 1 · Step 9 — `scripts/teardown.sh`

**Ported from `~/repos/memorywell/scripts/teardown.sh`**, reviewed against the
current version. This is the cost-control script — the most important thing in
the phase, and the one the nightly workflow depends on. Do not redesign it; port
it, then extend it with the two flags the workflow needs.

## What the port keeps

- `#!/usr/bin/env bash`, `set -euo pipefail`, sources `common.sh`.
- `--purge-vault` and `--shared` flags, parsed in a `for` loop with an unknown-arg
  error and usage message, plus `-h`/`--help`.
- Vault name `kv-${BASE_NAME}-${ENVIRONMENT}` → `kv-oop-dev`.
- `az account set`, then `log_vars` of what is about to be destroyed. The log
  matters: the workflow runs this unattended at 03:17 UTC.
- **Env RG first, always.** `az group delete --name $RG_NAME --yes --no-wait`,
  then the shared RG only with `--shared`. Reversed, a running container app
  tries to pull an image from a registry that is being deleted underneath it.
- `--no-wait` on both deletes, because RG deletion is slow and the nightly job
  should not burn its whole budget waiting.
- The `--purge-vault` loop: poll `az keyvault list-deleted` up to 30 attempts,
  10s apart, then `az keyvault purge`. If it never soft-deletes, **fail loudly**
  with the manual `az keyvault purge --name` command — not a silent skip. An
  un-purged vault blocks the next same-name deploy, and that failure shows up
  much later as a confusing deploy error.
- Without `--purge-vault`, print that purge was skipped and why.

Purge protection is off outside prod (`vault.bicep`, step 2), so this loop can
succeed on `dev`. If purge is ever refused with an authorization error, that is
RBAC, not the script — see `docs/CI_TEARDOWN.md` § 1.2.

## What the port adds — two flags for the workflow

`.github/workflows/teardown.yml` currently has `echo "to be implemented"` in four
steps whose comments name three invocations: `teardown.sh --precheck`,
`--purge-vault`, `--verify`. Add the two that are missing:

- **`--precheck`** — reports whether the env RG exists and whether the vault is
  soft-deleted, then exits **0** either way. It must never delete anything: this
  is what almost every nightly run executes, because almost every nightly run
  finds nothing to do, and the common case must cost nothing. The workflow uses
  its exit code to skip the destructive step.
- **`--verify`** — re-checks that `rg-oop-<env>` is gone and `kv-oop-dev` is
  not soft-deleted, and exits non-zero if either still holds. A silent partial
  teardown is the failure worth catching, because the cost it leaks is invisible
  until the next billing statement.

Both are safe to run on their own, which also makes them locally testable
without deploying anything.

## Verify

- `bash -n scripts/teardown.sh` clean.
- `./scripts/teardown.sh --help` prints usage and exits 0.
- `./scripts/teardown.sh --bogus` exits 1 with the usage line.
- **With nothing deployed:** `--precheck` reports both absent and exits 0,
  touching nothing.
- `./scripts/teardown.sh` with no flags deletes `rg-oop-dev` and keeps
  `rg-oop-shared`.
- `az group show --name rg-oop-dev` then fails with "not found" — give the
  managed environment a minute or two; it is async.
- `./scripts/teardown.sh --purge-vault` deletes the RG, waits for
  `kv-oop-dev`, purges it, and ends with a success line.
- `az keyvault list-deleted --query "[?starts_with(name,'kv-oop')].name"` is
  empty afterwards.
- `./scripts/teardown.sh --verify` exits 0. This is the check that would have
  caught a failed teardown — test it deliberately, including by re-running the
  destructive path and verifying _before_ it finishes.
- **The drain is slow.** `az group delete --no-wait` returns immediately, but the
  Container Apps managed environment took **~30 minutes** to finish deleting in
  a real run here — it is by far the slowest part of a teardown. `--verify` polls
  for up to 40 min for that reason, and the workflow's `timeout-minutes` must
  exceed it: a shorter budget reports a false failure on a teardown that is
  succeeding, which is worse than a slow check. Do not shorten either.
- **Deploy from an absent RG with `./scripts/deploy.sh`.** This is the real
  proof: if the vault were still soft-deleted, this fails.
- After teardown, `az group list --query '[].name' -o tsv` shows
  `rg-oop-shared` and no `rg-oop-dev`.
