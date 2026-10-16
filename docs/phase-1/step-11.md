# Phase 1 · Step 11 — CI guards, `docs/architecture.md`, final verification

The phase is not done until the gates in `.github/workflows/ci.yml` actually
gate. Right now `test`, `infra` and `shell` are wrapped in `hashFiles` guards that
no-op until their directories land — and `AGENTS.md` is explicit that a
permanently-skipped gate is worse than no gate.

## 1. Remove the three `hashFiles` guards

Each job's `if:` exists only because the directories were absent. Delete them
all, and delete the comment above each explaining why the guard was there —
leaving a comment that justifies a condition that no longer exists is worse than
the condition.

```yaml
test:
  name: Tests (api)
  runs-on: ubuntu-latest
  timeout-minutes: 10
  # guard removed here
  steps:
```

The same goes for the `infra` job's "Guard so this job is green on the docs-only
scaffold" comment.

## 2. Make shellcheck a real gate

`.github/workflows/ci.yml` runs shellcheck with `continue-on-error: true` and
`--exclude=SC2148`, because the ported memorywell scripts carry SC2155
(`export X="$(...)"` — masks a failed command's exit status) and `common.sh` has
no shebang to find.

Fix both rather than carrying the exemptions forward:

- **SC2155** in `common.sh`: split each `export X="$(...)"` into
  `X="$(...)"` then `export X`. This is a real bug class, not a lint nit — the
  combined form loses the command's exit status.
- **SC2148**: `common.sh` is sourced, never executed. The cleanest fix is a
  shebang plus the sourced-file idiom at the top
  (`#!/usr/bin/env bash` + `# shellcheck shell=bash` + an early return when
  sourced). Confirm `bash -n` still passes and the sourcing scripts are unaffected.

Then drop `--exclude=SC2148` and remove `continue-on-error: true`.

**If you would rather carry the exemptions into Phase 2**, that is defensible —
but then leave a comment saying so explicitly, and re-run `shellcheck` locally
with the same flags CI uses. A silent exemption rots.

## 3. `docs/architecture.md`

Not yet written, and `docs/PLAN.md` § Architecture defers a specific item to it:
the **occurrence split threshold**. Record it there rather than losing it —

> Split when a single repeatable exceeds ~5,000 occurrences, or a plan exceeds
> ~50,000 objectives. At that point add a second container with partition key
> `/objectiveId` and move `occurrence` into it.

Plus: the deployed resource topology as it actually exists (which group holds
what, and why ACR and App Configuration are shared), and the two identities and
what each is granted.

Keep it short. `PLAN.md` remains the source of truth; this is the as-built view.

## 4. Full local verification

Run all of these from the repo root before pushing. They are the same commands
CI runs, and `AGENTS.md` says fix locally first.

```bash
pytest -q                          # from api/ only — see below
az bicep build --file infra/main.bicep --stdout > /dev/null
az bicep build --file infra/shared.bicep --stdout > /dev/null
bash -n scripts/*.sh
shellcheck --severity=warning scripts/*.sh
pre-commit run --all-files
```

- `pytest -q` **from `api/`** — to match CI's `working-directory`. It also works
  from the repo root (the tests insert `api/` onto `sys.path` themselves), so
  this is a consistency habit, not a hard requirement.
- `az bicep version` must print **0.48.1**. If it does not, `BICEP_VERSION` in
  `ci.yml` and the local format hook disagree, and CI's diff check fails on
  formatting nobody changed. Fix the version, not the bicep.
- `pre-commit run --all-files` is CI's baseline and is fine to run locally as a
  deliberate full check — it is the one exception to "hooks run on staged files".

## 5. Repo hygiene

- `git status --short` — only intended files. No `.env`, no `infra/*.json` build
  output, no `.pytest_cache`, no `.ruff_cache`, no deploy logs.
- `git check-ignore -v .env` still reports ignored.
- `grep -rn "memwell" docs/ .github/ scripts/ infra/ api/` — nothing. The port's
  provenance is one line in each ported script's header comment, not a scatter
  of the old project's names.
- Confirm `.gitignore` covers anything the new directories introduced.

## Verify

- Push and open the PR. All four CI jobs (`lint`, `test`, `infra`, `shell`)
  report as **real runs**, not skips. A skipped `test` job means a guard
  survived.
- `shellcheck` runs without `continue-on-error` and passes.
- `pytest -q` in the CI log shows 2 passed.
- The `infra` job's format diff is empty.
- **Then tear down**, and confirm the nightly workflow is intact and green on a
  pre-check dispatch. Do not disable it to leave the environment up.

Phase 1 is done when the review gate in [`_brief.md`](_brief.md) § 7 passes and
the meter is stopped.
