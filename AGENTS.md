# AGENTS.md — objective-oriented-planning

> Source of truth: `docs/PLAN.md` (+ `docs/INITIAL_IDEA.md` for product context).
> Do not diverge from the plan without updating it first. Ideas about where the
> project _should_ go belong in
> `~/repos/think-tank/objective-oriented-planning/FUTURE.md` (outside this repo),
> never in the plan.

## Current state

Phase 1 is **built but not yet committed** — `infra/`, `api/` and `scripts/`
exist and have been deployed live, teardown and redeployed. See
`docs/phase-1/_brief.md` for the step files and § Build mode below for how it
was built. `web/` does not exist yet; theming lands with it in Phase 4.

`.github/workflows/teardown.yml` is **armed**: every step delegates to
`scripts/teardown.sh` (`--precheck` → `--purge-vault` → `--verify`) and no
`az group delete` is inlined, because the script holds the pre-check, the
ordering and the verification. It still deletes nothing until its OIDC setup is
done — see `docs/CI_TEARDOWN.md` § 1–2 for the app registration, RBAC,
federated credential and GitHub environment. Until that is configured, a nightly
run fails at `azure/login`, and that is the safe failure.

The `test`, `infra` and `shell` CI jobs are **unguarded** as of Phase 1 — the
`hashFiles` guards are gone and all four jobs are real gates. If one ever goes
back to skipping, that is a regression: a permanently-skipped gate is worse than
no gate.

## Workflow

- Changes land via branch + PR into `main`. Do not push to `main` directly.
- After checkout run `pre-commit install` once. Hooks run on `git commit` and only
  touch staged files. Never `pre-commit run --all-files` except for a deliberate
  baseline — CI does that.
- `.github/workflows/ci.yml` is the merge gate (pre-commit, `pytest`,
  `bicep build` + format diff, `bash -n`, shellcheck). Every PR into `main` must
  be green; fix locally first.

### Verifying before you push

- Python: `pytest -q` **from `api/`**, matching CI's `working-directory`. The
  tests insert `api/` onto `sys.path` themselves so a repo-root run also works,
  but run it the way CI does or a local pass tells you nothing. Single test (from
  Phase 2 onward): `pytest tests/test_rollup.py::test_unassigned_child -q`.
- **Never run another project's scripts from this repo's directory.** Our scripts
  now resolve templates and the API context through `$ROOT`
  (`$ROOT/infra/main.bicep`, `$ROOT/api`), so they act on _their own_ repo no
  matter where they are invoked from — but memorywell's older copies still use
  relative paths, so running one of those from here resolves _our_ template and
  creates memorywell's resources in _our_ subscription. `cd` into the owning repo
  first when using another project's scripts.
- Every `az` / `curl` call in `scripts/` goes through `run`, `run_hide_stderr`
  or `run_quiet`, which echo `+ <cmd>` to **stderr** and append it to
  `logs/<name>-<ts>.log`. Keep it that way: the stderr split is what lets
  `X=$(run az ...)` capture only the command's output. Moving either `run` or
  `init_command_log` to stdout silently corrupts every `$(...)` capture. And
  never append `2>/dev/null` to `run` — that redirects `run` itself and swallows
  the trace; use `run_hide_stderr`. `logs/` is git-ignored.
- **Deployment names are minted lazily** (`deployment_name`, `image_tag`), never
  at source time. Keep it that way: `deploy-all.sh` and `teardown.sh --precheck`
  source `common.sh` but never deploy, so an eager name would overwrite
  `$LAST_DEPLOYMENT_FILE` and make the next real deploy reuse a stale timestamp.
- **Read ARM outputs with `fetch_deployment_outputs`, never a bare
  `az deployment sub show`.** Outputs can lag the deployment's `Succeeded` state
  (eventual consistency), and `az -o tsv` drops null columns entirely, so a bare
  read yields a silently empty `APP_NAME` and a baffling failure one command
  later.
- **`az account set` before any diagnostic query.** The CLI caches its active
  subscription across contexts, so an unqualified `az group show` can report a
  group "not found" in one shell and `Succeeded` in the next, sending you chasing
  a phantom bug. Pass `--subscription` explicitly when verifying.
- Bicep: `az bicep build --file infra/main.bicep --stdout`, and format check via
  `az bicep format --indent-kind Space --indent-size 2 --insert-final-newline
--file <f>`.
- Shell: `bash -n scripts/*.sh` and `shellcheck --severity=warning scripts/*.sh`.
- `shellcheck` is a **real gate** in CI — no `--exclude` and no
  `continue-on-error`. `common.sh` splits `export X="$(...)"` into a separate
  assignment (SC2155 masks a failed command's exit status) and carries a shebang
  plus a sourced-file guard (SC2148). Do not reintroduce either exemption: an
  exclusion that exists to survive new code is an exclusion nobody reviews.
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

### Phase 1 exception — agent-implemented (2026-10-15)

**Phase 1 was built by the agent, not by hand**, at the owner's explicit
instruction. Steps 1–11 were implemented and deployed live against the
development subscription. Steps 2–4 remain accurate as instruction; steps 8, 8a
and 9 carry corrections from what the live runs revealed (see below).

This is an exception, not a change of mode. **Phases 2+ follow the contract
above** unless the owner says otherwise at the time. If a phase is ever
agent-implemented again, record it here the same way rather than leaving the
docs claiming a build style that did not happen.

Two findings from the live runs are worth carrying forward, because both looked
right until exercised against Azure:

- **Do not add `revisionMode` to the container app.** It is rejected by Bicep's
  type checker on every API version that has types (BCP037), which fails the whole
  deployment. Container Apps already mints a new revision on every
  `az containerapp update --image`; a lone revision after a first deploy is a
  provisioning race, not single-revision mode. Confirm by deploying again before
  changing anything.
- **A teardown takes ~30 minutes**, almost entirely the Container Apps managed
  environment draining. `teardown.sh --verify` polls ~40 min and the workflow's
  `timeout-minutes` is 60 for that reason. Do not shorten either: a false
  "still exists" fails the nightly job on a teardown that is succeeding.

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
- **Teardown waits are bounded by the slowest resource, and a short budget fails a
  working teardown.** The managed environment takes ~16-30 min to drain, so
  `teardown.sh` waits up to ~20 min for the vault to soft-delete and ~40 min for
  the group to vanish, and the workflow allows 90 min. Do not shorten them.
- **"Not found" is ambiguous right after an RG delete.** For ~12 s afterwards the
  Key Vault is neither live nor soft-deleted. Skip the purge only when the vault
  was **not live when the run started** (`VAULT_WAS_LIVE`, probed *before* the
  delete) — not when "no group was deleted this run", which wrongly blocks the
  skip on a re-run while the group is still draining. Getting this wrong either
  leaves the vault soft-deleted (blocking the next deploy) or waits 20 min for a
  vault that will never appear.
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
