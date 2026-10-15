# AGENTS.md — objective-oriented-planning

> Source of truth: `docs/PLAN.md` (+ `docs/INITIAL_IDEA.md` for product context).
> Do not diverge from the plan without updating it first. Ideas about where the
> project _should_ go belong in
> `~/repos/think-tank/objective-oriented-planning/FUTURE.md` (outside this repo),
> never in the plan.

## Current state

Phase 1 has **not started**. This repo is documentation and governance only —
`infra/`, `api/`, `web/`, `scripts/` do not exist yet. **Never assume code
exists; check first.**

`.github/workflows/teardown.yml` exists but is an **inert skeleton**: every step
is `echo "to be implemented"` because `scripts/teardown.sh` has not landed. It
runs on schedule and deletes nothing. Do not infer from reading it that teardown
is live, and do not "arm" it by pasting in an `az group delete` before the real
script exists — that would delete a resource group with no pre-check and no
verification. `docs/CI_TEARDOWN.md` is still a Phase 1 deliverable.

The `test`, `infra` and `shell` CI jobs are guarded by `hashFiles` so they no-op
until those paths arrive. Remove each guard as its directory lands; a
permanently-skipped gate is worse than no gate.

## Workflow

- Changes land via branch + PR into `main`. Do not push to `main` directly.
- After checkout run `pre-commit install` once. Hooks run on `git commit` and only
  touch staged files. Never `pre-commit run --all-files` except for a deliberate
  baseline — CI does that.
- `.github/workflows/ci.yml` is the merge gate (pre-commit, `pytest`,
  `bicep build` + format diff, `bash -n`, shellcheck). Every PR into `main` must
  be green; fix locally first.

### Verifying before you push

- Python: `pytest -q` **from `api/`** — tests import the app via a `sys.path`
  insert, so a repo-root `pytest` will not resolve it. Single test:
  `pytest tests/test_rollup.py::test_unassigned_child -q` (still from `api/`).
- Bicep: `az bicep build --file infra/main.bicep --stdout`, and format check via
  `az bicep format --indent-kind Space --indent-size 2 --insert-final-newline
--file <f>`.
- Shell: `bash -n scripts/*.sh` and
  `shellcheck --severity=warning --exclude=SC2148 scripts/*.sh`.
- `shellcheck` is `continue-on-error` in CI today: the ported memorywell scripts
  still carry SC2155 (`export X="$(...)"`) and source `common.sh`, so there is no
  shebang for SC2148. Drop the guard once those are cleaned up.
- `BICEP_VERSION` (currently `v0.48.1`) in `ci.yml` must be kept in step with the
  `az bicep` version installed locally, or formatting differs between the hook and
  CI's diff.
- CI pins Python `3.11` literally, **not** via `.python-version` — that file is
  git-ignored, so do not rely on it existing locally either.

## Build mode: learning-first, agent-guided

- The human builds by hand. The agent does **not** big-bang implement.
- Work is **strictly sequential**, starting at **Phase 1**. One phase at a time, no
  skipping ahead, no pre-implementation of future phases. Scaffolding a Phase 2
  field in Phase 1 is tempting and wrong.
- Each phase follows this contract:
  1. Agent writes `docs/phase-<n>/`: `_brief.md` (goal, concepts, prerequisites,
     ordered-step index, file outline with paths and stubs rather than
     implementations, manual verification checks, demo gate) plus one `step-x.md`
     per ordered step carrying that step's instructions, stub shapes and its own
     verification checks.
  2. Human implements by hand following the brief. Agent answers questions and
     unblocks on errors but does not take over.
  3. Agent sanity-checks what was built (human shows or pastes output) before the
     next phase brief is issued.

## Repo rules

- Planned layout (`docs/PLAN.md` § Repo layout): `infra/ api/ web/ scripts/ docs/`.
  Scaffold only what the current phase brief needs.
- **Port, don't design, the cost-control scripts.** `teardown.sh`, `common.sh`,
  `deploy.sh` and `deploy-shared.sh` come from `~/repos/memorywell/scripts/`,
  reviewed against the current versions — they were written for memorywell's
  Phase 1. Do not write a fresh teardown script.
- Azure-first on the AI-200 stack; IaC is Bicep. Postgres, Redis, Service Bus,
  Event Grid and Functions are **deliberately absent** until a phase needs one.
- Cheapest viable tier of every service: Cosmos serverless, Container Apps
  scale-to-zero, App Configuration free tier, ACR Basic, Key Vault Standard,
  Log Analytics pay-per-GB. Estimated ~$5-6/month while running.
- `scripts/teardown.sh` must exist from Phase 1; destroy resources between study
  sessions. Delete the environment RG (`rg-oop-<env>`) **before** the shared one —
  reversed, a running container app can try to pull images mid-teardown.
  `rg-oop-shared` (ACR + App Configuration) is kept by default — pass `--shared` to
  delete it too, and `--purge-vault` to purge the soft-deleted vault that otherwise
  blocks the next same-name deploy (RG deletion is async, so nightly runs purge,
  local runs do not).
- The nightly `.github/workflows/teardown.yml` is **cost-control infrastructure,
  not a development convenience.** Do not delete, disable or comment it out when a
  phase ends, a deploy breaks, or the project goes quiet. Its whole value is that
  it fires when nobody is watching. Cheap pre-check first: skip all destructive
  steps if the environment RG is absent and no vault is soft-deleted.
- Auth with **OIDC** (`azure/login` + `id-token: write`), never a stored client
  secret. Secrets never committed; managed identities + Key Vault references
  everywhere. `.env` stays local and git-ignored, so CI injects `BASE_NAME` /
  `LOCATION` / `ENVIRONMENT` via repo variables and `AZURE_SUBSCRIPTION_ID` via
  secrets.

## Formatting (enforced by `.pre-commit-config.yaml`)

- Python (`api/`): Ruff lint + format per `pyproject.toml` — 100 cols, target
  `py311` (no newer syntax), rules `E,F,I,UP,B`, double quotes.
- TS/JS/JSON/CSS/Markdown/YAML: Prettier per `.prettierrc.json`
  (`proseWrap: preserve`, so the long hand-written lines in `docs/` are
  intentional — do not rewrap them). Prettier skips `LICENSE` and `*.bicep`.
- Bicep: `az bicep format` local hook (Space, indent 2). CI checks formatting by
  diffing a formatted copy, so it fails on drift instead of rewriting files.
- LF endings and a final newline everywhere (EditorConfig). This has been enforced
  from the first commit on purpose; do not "fix" the config to accommodate a
  hand-edited file.

## Domain invariants (do not break)

Settled in `docs/PLAN.md`, and they carry the reasoning that produced them. If one
appears wrong, fix the plan first, then the code.

- **One plan = one objective.** Children are objectives; the tree is recursive.
- **Weight lives on the relationship, not the objective.** An objective has no
  weight of its own; only the parent's owner may write a child's weight. A helper
  cannot re-weight themselves or a sibling.
- **Rollup** is `Σ(childPercent × childWeight) / Σ(childWeight)`. Unassigned
  children count in the denominator at 0% — the drag is the point. Abandoned
  children leave both numerator and denominator, and the count stays visible.
- **A childless parent is `null`, rendered `—`, not 0%.** Nothing-defined and
  defined-but-unstarted are genuinely different states.
- **An abandoned plan has no percent; an archived one keeps it.** Deliberate
  asymmetry, not an oversight.
- **Repeatables are bounded blocks, never open-ended habits.** `targetCount` and
  `endDate` are required, which is what makes SMART structural rather than
  aspirational. Scoring is derived **on read**, never stored. Excess caps at 100%;
  today is pending, not failed.
- **Renewal links history, never copies it.** And **archiving never renews** —
  bulk renew is a separate, explicit action taken beforehand.
- **One IANA timezone per plan**, owner-set. It governs cadence day boundaries and
  `endDate`. Changing it affects future boundaries only; a scored verdict is
  immutable.
- **Optimistic concurrency on every write** via `_etag`. Mismatch → `409` + a
  client refetch. No last-write-wins path anywhere, ever.
- **Any write resets the inactivity clock** — status, detail, an answer, or an
  occurrence log. You are coached on silence, not on slowness.
- **Roles are owner / helper / observer**, scoped to a single plan. A helper edits
  freely _inside their own subtree_ and read-only above it, except for `proposal`
  rows raised upward. Abandon and redact authority both mirror subtree scope; the
  owner may act anywhere. Enforcement is server-side, never client-side.
- **Observer visibility is three orthogonal filters**, all server-side:
  **visible iff `(granted OR grants are empty) AND NOT denied`.** Redaction always
  wins.
  - Grants are a per-node allowlist with **no subtree inheritance**.
  - Empty grants means **no restrictions** — the whole plan at the observer's tier.
    An explicit selection, distinct from granting the root alone.
  - Redaction **does** cascade to the whole subtree, is **labelled** rather than
    silent, and a redacted objective **still counts in the rollup** so the
    arithmetic keeps adding up.
  - Tier: `full` is "see exactly what a helper sees, write nothing" — it inherits
    the helper read surface so new fields are audited once, not twice. `progress`
    is public-only, and additionally hides the two things nobody authored: helper
    names and coach cards.
  - Notes, detail text and clarifying answers carry `isPublic`, set at write time
    by their author (owner may override). **Occurrence logs carry no flag** —
    logging is an act, not a statement, and flagging it would make a block's own
    arithmetic unexplainable to observers.
- **A `409` protects data, but a decided action is never an error.** Approving a
  proposal that has gone stale shows the owner what changed and lets them
  re-approve or abandon it. No retry dead end, no lost proposal.
- **AI writes are always staged for human approval.** Nothing auto-applies. SMART
  checking is mostly _structural_ — the AI only catches vague, unevidenced and
  implausible objectives. Coaching a repeatable is opt-in and heavily damped: one
  card, then silence. A recurring "you haven't walked yet" prompt is the failure
  mode that gets these apps deleted.

## Verification

- Per-phase manual checks, plus `pytest` on the pure functions — rollup, block
  scoring, timezone boundaries — which is where the correctness risk actually
  lives. The full list is `docs/PLAN.md` § Verification; treat it as the gate for
  the phase it belongs to, not as a wish list.
- Every phase is cost-constrained. Before any phase is called done, confirm the
  environment can still be torn down and that the teardown workflow is intact.
