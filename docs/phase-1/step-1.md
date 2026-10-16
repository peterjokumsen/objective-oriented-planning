# Phase 1 · Step 1 — Scaffold empty layout

Create the directories the phase needs, empty. Nothing else — no placeholder
files, no `.gitkeep`, no code.

```plaintext
infra/
infra/modules/
api/
api/tests/
scripts/
```

Then write `.env.example` at the repo root. It is the template a human copies to
`.env`; it holds **no secrets**, and `.env` itself is already git-ignored.

```bash
BASE_NAME=oop
ENVIRONMENT=dev
LOCATION=westeurope
SUBSCRIPTION_ID=
```

Notes:

- `BASE_NAME=oop` because `docs/PLAN.md` names the groups `rg-oop-<env>` and
  `rg-oop-shared`. Everything derives from it, so it is worth getting right
  before step 6 rather than after.
- No `web/`. Theming is Phase 4 — see `_brief.md` § 1.
- No `POSTGRES_ADMIN_PASSWORD`, no `CLIENT_IP`: there is no Postgres here, and
  `CLIENT_IP` existed only to open a firewall for it.
- Leave `SUBSCRIPTION_ID` blank in the committed template and fill it in your
  local `.env`.

## Verify

- `git status --short` shows the new directories and `.env.example`, and no
  `.env`.
- `ls infra api scripts` — empty apart from `infra/modules` and `api/tests`.
- `git check-ignore -v .env` confirms `.env` is ignored.
