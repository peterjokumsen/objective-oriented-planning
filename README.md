# objective-oriented-planning

Declare one objective; AI decomposes it into a weighted tree you and your helpers
actually keep moving. Recurring work is a **bounded block**, not an open-ended
habit.

> **Status:** Phase 1 — Foundation. **In progress.** The brief lives in
> [`docs/phase-1/`](docs/phase-1/_brief.md) and is being built by hand; there is
> still no application code in the repo.

## What it is

One plan is one declared objective. The steps needed to reach it are themselves
objectives, so a plan is a **recursive tree** rather than a flat list, and
progress rolls up the tree by weight.

People join in two ways:

- **Helpers** own an assigned subtree, edit freely inside it, and propose
  changes upward for the owner to approve.
- **Observers** are read-only and filtered three ways — a per-node grant set, a
  per-observer denyList, and a visibility tier.

Every objective is SMART, so nothing runs forever. A repeatable is a finite
block (`Walk 5 minutes a day, 5 days per week, 3 Nov – 13 Dec`) that resolves to
**successful** / **partial** / **missed** and can be renewed into a fresh block
that links its history rather than copying it.

The AI has one job with three parts: **clarify** a vague objective before
anything else, **decompose** it into weighted children as staged proposals the
owner must approve, and **coach** stalled or blocked leaves with dismissible
cards. Nothing is ever applied automatically.

## Documentation

| File                                           | What it is                                                                                 |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------ |
| [`docs/PLAN.md`](docs/PLAN.md)                 | **Source of truth.** Architecture, domain rules, decisions, phase table, verification list |
| [`docs/INITIAL_IDEA.md`](docs/INITIAL_IDEA.md) | The original brief the plan derives from — product context, not specification              |
| [`AGENTS.md`](AGENTS.md)                       | How work happens in this repo: workflow, phase contract, invariants, formatting            |

Later ideas about where the project should go live in
`~/repos/think-tank/objective-oriented-planning/FUTURE.md`, not in the plan.

## Build status

Phases are **strictly sequential, one brief at a time** — no skipping ahead and
no pre-implementation of later phases. Full table in `docs/PLAN.md` § Build
phases.

| #   | Phase                                                                 | State           |
| --- | --------------------------------------------------------------------- | --------------- |
| 1   | Foundation — Bicep, repo scaffold, teardown + nightly CI teardown     | **in progress** |
| 2   | Data + core API — Cosmos, domain types, pure rollup and block scoring | not started     |
| 3   | Identity + invites                                                    | not started     |
| 4   | Tree UI + permissions                                                 | not started     |
| 5   | Coach agent                                                           | not started     |
| 6   | Unattended coaching                                                   | not started     |
| 7   | Observability + hardening                                             | not started     |

Each phase begins with an agent-written brief under `docs/phase-<n>/`, is
implemented by hand, and closes with a review gate.

## Working in this repo

- `pre-commit install` once after checkout. Hooks run on staged files at commit
  time; CI runs the full set on every PR.
- CI (`.github/workflows/ci.yml`) is the merge gate: pre-commit, `pytest`,
  `bicep build`, shell syntax.
- Deploys are manual. `./scripts/deploy-all.sh` provisions shared resources then
  the environment; `./scripts/check-state.sh` reports provisioning state and exits
  non-zero if anything is not `Succeeded`. Every `az` call is recorded to a
  git-ignored `logs/<script>-<timestamp>.log`.
- The nightly [`teardown`](.github/workflows/teardown.yml) workflow exists so the
  meter stops when nobody is paying attention — do not delete or disable it. It
  is armed and delegates to `scripts/teardown.sh`; it needs the one-time OIDC
  setup in [`docs/CI_TEARDOWN.md`](docs/CI_TEARDOWN.md) before it can log in.
- Azure-first, IaC is Bicep. Cheapest viable tier of every service; nothing runs
  between study sessions.

## Cost

Estimated **~$5-6/month while running**, near **$0 with the environment torn
down**. ACR Basic and the Key Vault are the only always-on costs, which is
precisely why the ACR lives in a shared resource group.

## License

MIT — see [`LICENSE`](LICENSE).
