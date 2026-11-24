# Phase 4 Brief — Documentation review / single source of truth

> **Status: not started.** Phase 3 (Data + core API) is complete and committed
> (PR #8). This brief follows the contract in `AGENTS.md` § Build mode: human
> builds by hand; agent sanity-checks before the next brief.

## 1. Goal

Make the documentation a reliable single source of truth so status claims cannot
drift the way they did between Phases 1–3 (stale `AGENTS.md`, stale phase-3
brief, stale phase table). Concretely:

- `PLAN.md` contains only **current + upcoming** phases at the top, plus a short
  "Completed" footnote section of one-line summaries with links.
- Completed-phase detail lives in `docs/phase-N/` and topic READMEs, never
  duplicated into `PLAN.md`.
- A `docs/README.md` index maps every topic to its authoritative doc + owner.
- A CI check (and matching local script) enforces consistency, link validity and
  (via `jscpd`) no copy-paste duplication.

Nothing user-facing ships; the deliverable is documentation hygiene + tooling.

## 2. Concepts practised

- Single source of truth per domain; doc ownership.
- Copy-paste detection with `jscpd`.
- Markdown link validation in CI.

## 3. Prerequisites

- Phases 1–3 committed (true).
- `jscpd` available as a dev dependency.

## 4. Ordered steps

1. **Inventory** — list every `.md` under `docs/` and top-level; assign each a
   single owner/authoritative location; record in `docs/README.md`.
2. **Move completed detail out of PLAN.md** — keep one-line summaries + links in
   a "Completed" footnote section at the bottom of PLAN.md; detail stays in
   `docs/phase-N/` and topic READMEs.
3. **Topic README stubs** — create `apps/web/README.md`, `bffs/api-bff/README.md`,
   `backends/*/README.md`, `infra/README.md`, `scripts/README.md` with scope,
   owner, how-to-run, and links to the authoritative docs. No duplicated
   invariants.
4. **Reconcile AGENTS.md** — "Current state" points at PLAN.md; no duplicated
   status claims.
5. **Update `docs/architecture.md`** — record occurrence split threshold and any
   other deferred notes so it is current.
6. **CI check** — add `scripts/check-docs.sh` (current-phase consistency, link
   validity, jscpd duplication) and wire into `.github/workflows/ci.yml`; add
   `npm run check:docs` (or `pnpm`) script for local parity.
7. **jscpd config** — `.jscpd.json` with sensible thresholds (e.g., min 50 tokens,
   5% max duplication) scoped to `docs/` + top-level READMEs/AGENTS.md.

## 5. File outline (stubs, not implementations)

- `docs/README.md` — index
- `docs/phase-4/_brief.md` (this file) + `step-x.md`
- `apps/web/README.md`, `bffs/api-bff/README.md`, `backends/domain/README.md`,
  `backends/data/README.md`, `infra/README.md`, `scripts/README.md`
- `scripts/check-docs.sh`
- `.jscpd.json`
- `package.json` — add `jscpd` devDependency + `check:docs` script

## 6. Manual verification

- `./scripts/check-docs.sh` passes locally.
- `pnpm check:docs` matches CI.
- PLAN.md top contains only current + upcoming phases; completed work is linked,
  not inlined.
- `docs/README.md` lists every `.md` under `docs/`.

## 7. Demo gate

Show: PLAN.md with a short "Completed" footnote section; `docs/README.md` index;
a passing `check-docs.sh` run; and a deliberately duplicated paragraph that the
check rejects.
