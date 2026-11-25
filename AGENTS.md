# AGENTS.md — objective-oriented-planning

Monorepo for an objective-oriented planning system. Source of truth: `docs/PLAN.md` (product context in `docs/INITIAL_IDEA.md`). Do not diverge from the plan without updating it first.

## Project Overview & Architecture

- Angular 22 frontend (Nx workspace, Vitest unit tests, Playwright E2E), Python 3.11 FastAPI-style API, Bicep IaC, cost-control shell scripts.
- Azure-first (AI-200 stack): Cosmos serverless, Container Apps scale-to-zero, App Configuration free, ACR Basic, Key Vault Standard, Log Analytics pay-per-GB.
- Key dirs: `apps/` (Angular apps), `backends/`, `bffs/`, `libs/` (shared), `api/` (Python), `infra/` (Bicep), `scripts/` (deploy/teardown), `docs/`, `.github/workflows/`.
- Nx config in `nx.json`; workspace `pnpm-workspace.yaml`.

## Commands

- Install (JS): `pnpm install`
- Install (Python): `cd api && pip install -r requirements.txt`
- Build all: `npm run build` (nx run-many -t build)
- Test all: `npm run test` (nx run-many -t test)
- Lint: `npm run lint`
- Typecheck: `npm run typecheck`
- Python tests (from `api/`): `pytest -q` (CI uses working-directory `api/`); single: `pytest tests/test_rollup.py::test_unassigned_child -q`
- Bicep build+format: `./scripts/validate-bicep.sh`
- Shell syntax: `bash -n scripts/*.sh`
- Shellcheck: `shellcheck --severity=warning scripts/*.sh`
- Logging check: `./scripts/check-logging.sh`
- Docs check: `npm run check:docs`

## Active Phase Workflow

**Current Phase:** Found by checking the first to be implemented phase in `PLAN.md`

When making automated changes, strictly follow this loop:

1. **Scope Lock:** Only implement tasks listed under the **Current Phase** in `PLAN.md`. Do not refactor or scaffold work belonging to future phases.
2. **Execute & Verify:** Implement one task at a time. Run `<test-and-lint-command>` after each change and fix any failures before moving on.
3. **Update State:** Mark completed tasks `[x]` in `PLAN.md` as you finish them.
4. **Phase Gate:** When all tasks in the current phase are `[x]` and all checks pass, stop and summarize completed changes—do not auto-advance to the next phase unless explicitly instructed.

## Code Style & Patterns

- Python: Ruff lint+format, 100 cols, target py311, rules E,F,I,UP,B, double quotes (see `pyproject.toml`).
- TS/JS/JSON/CSS/MD/YAML: Prettier (`.prettierrc.json`, proseWrap preserve). Bicep: `az bicep format --indent-kind Space --indent-size 2 --insert-final-newline`.
- LF endings + final newline (`.editorconfig`). Pre-commit hooks via `pre-commit install`.
- Domain invariants in `docs/PLAN.md` (one plan=one objective, weight on relationship, rollup formula, optimistic concurrency via `_etag`, roles owner/helper/observer, etc.) — do not break.
- Never add `revisionMode` to container app (Bicep type-checker rejects).

## Testing Guidelines

- Frameworks: Vitest (Angular), pytest (Python), Playwright (E2E via Nx plugin).
- Run from `api/` for Python. Tests insert `api/` onto sys.path.
- Required before finishing: pytest, bicep build+format, bash -n, shellcheck, check-logging, pre-commit.

## Git & Safety Boundaries

- Branch + PR into `main`; never push to `main` directly. Branch name `phase-<n>-<brief-summary>`. One phase per branch/PR.
- Commit messages: conventional-ish (`Phase N: ...`, `docs:`, `fix:`, `refactor:`, `build(deps):`). See git log.
- Do not edit manually: `pnpm-lock.yaml`, generated build artifacts (`build/`, `dist/`), `.pytest_cache/`, `.ruff_cache/`.
- Secrets never committed; `.env` local/git-ignored. CI injects `BASE_NAME`/`LOCATION`/`ENVIRONMENT` via repo vars and `AZURE_SUBSCRIPTION_ID` via secrets.
- Teardown workflow (`.github/workflows/teardown.yml`) is cost-control infra — do not delete/disable.
- OIDC auth only (`azure/login` + `id-token: write`), never stored client secrets.
