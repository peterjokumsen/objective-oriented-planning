# Phase 3 Brief — Data + core API

> **Status: not started.** Phase 2 (Architecture, frameworks & UI skeleton) is
> complete and committed (PR #7). This brief follows the contract in
> `AGENTS.md` § Build mode: human builds by hand; agent sanity-checks before
> the next brief.

## 1. Goal

Add the data layer and the core API surface that Phases 4+ build on:

- **Cosmos DB serverless**, single container partitioned by `planId`.
- **Domain types** including `timezone`, tier, grant, `isPublic` fields.
- **Weighted rollup** and **block scoring** as pure, unit-tested functions.
- **`_etag`-checked write path** (optimistic concurrency → `409`).

Nothing user-facing ships; the deliverable is a data model and pure functions
that Phase 4 (Identity + invites) and Phase 5 (Tree UI) consume.

## 2. Concepts practised

- Cosmos serverless provisioning via Bicep (environment RG).
- Pure functions for rollup/scoring with timezone-aware day boundaries.
- Optimistic concurrency on every write (`_etag`).

## 3. Prerequisites

- Phase 1 infra deployed (or redeployable) and teardown working.
- Phase 2 Nx monorepo in place (`apps/`, `libs/`, `bffs/`, `backends/`).
- `pytest` runnable from `api/` (or the new backend test project).

## 4. Ordered steps

1. **Cosmos provisioning** — add `cosmos.bicep` module; container with
   partition key `/planId`; serverless. Wire into `infra/main.bicep`.
2. **Domain types** — `Plan`, `Objective`, `Participant`, `RepeatableBlock`,
   `Proposal`, `Grant`/`Deny` structures; `timezone`, tier, `isPublic`.
3. **Rollup function** — `Σ(childPercent × childWeight) / Σ(childWeight)`;
   unassigned children at 0%; abandoned excluded from both; childless → `null`.
4. **Block scoring** — on read: end date passed + log meets target →
   successful; ≥50% → partial; else missed; excess capped at 100%; today
   pending.
5. **Write path with `_etag`** — every write carries `_etag`; mismatch → `409`.
6. **Unit tests** — rollup, block scoring, timezone boundaries, concurrency.

## 5. File outline (stubs, not implementations)

- `infra/modules/cosmos.bicep`
- `backends/.../Domain/Plan.cs` (or chosen location) — types
- `backends/.../Rollup.cs` — pure function
- `backends/.../BlockScoring.cs` — pure function
- `tests/RollupTests.cs` etc.

(Exact paths to be settled when the human picks the .NET project layout.)

## 6. Manual verification

- Deploy; create a plan document in Cosmos via the API; read it back.
- Run unit tests green.
- Confirm teardown still works with the new resource.

## 7. Demo gate

Show: a plan with two children (weights 2 and 3), one at 50% and one at 100%,
rollup = 80%; an unassigned child drags it down; an abandoned child is excluded;
a childless parent renders `—`.
