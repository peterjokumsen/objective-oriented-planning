# Phase 1 · Step 6 — `scripts/common.sh`

Ported from `~/repos/memorywell/scripts/common.sh` per `AGENTS.md` § Repo rules
— reviewed against the current version, not copied blind. Every resource name
changes from the `memwell` prefix to `oop`; the shape is otherwise what the
deploy and teardown scripts in this repo depend on.

It has four jobs: load `.env`, compute names, mint a unique deployment name, and
provide output helpers.

## Sourced, not executed

`common.sh` has **no shebang** and is never run directly — it is sourced by
`deploy.sh`, `deploy-shared.sh` and `teardown.sh`. That is why CI currently runs
shellcheck with `--exclude=SC2148` ("shebang is missing") and
`continue-on-error`. Step 11 cleans both up; until then they are expected.

## Naming

```bash
export RG_NAME="rg-${BASE_NAME}-${ENVIRONMENT}"
export SHARED_RG_NAME="rg-${BASE_NAME}-shared"
export SHARED_ACR_NAME="$(echo "acr${BASE_NAME}" | tr '[:upper:]' '[:lower:]' | tr -d '-')"
```

So `BASE_NAME=oop ENVIRONMENT=dev` gives `rg-oop-dev`, `rg-oop-shared`,
`acroop` — matching `docs/PLAN.md` § Cost & safety exactly.

Required variables, with `dev` as the only default:

```bash
: "${BASE_NAME:?set BASE_NAME in .env}"
: "${ENVIRONMENT:=dev}"
: "${LOCATION:?set LOCATION in .env}"
: "${SUBSCRIPTION_ID:?set SUBSCRIPTION_ID in .env}"
```

Plus `registry_name()` and `login_server()` helpers, so `deploy.sh` has one place
that knows the registry's name.

Change memorywell's `LAST_DEPLOYMENT_FILE` to
`${TMPDIR:-/tmp}/oop-${BASE_NAME}-${ENVIRONMENT}.deployment`. It is a temp file
outside the repo, and leaving memorywell's prefix in it would collide across
projects on the same machine.

## Deployment name and image tag

`az deployment sub create` names must be unique per run — re-using one
overwrites history and confuses `az deployment sub show` lookups. So every run
mints `<base>-<env>-YYYYmmdd-HHMMSS` and records it; `REUSE_DEPLOYMENT=1` re-runs
against the previous name when debugging a failed deployment.

Then:

```bash
TIMESTAMP="${DEPLOYMENT_NAME##"${BASE_NAME}-${ENVIRONMENT}-"}"
export IMAGE_TAG="${ENVIRONMENT}-${TIMESTAMP}"
```

This is the mechanism behind "revisions day one", and it is easy to lose:
`deploy.sh` points the app at `api:${IMAGE_TAG}`, and Container Apps mints a new
revision when the image **string** changes. Re-pushing `api:dev` alone would
change nothing. Keep it.

## Output helpers

Colour auto-disabled when not a TTY or `NO_COLOR` is set, so CI logs stay plain:
`step`, `info`, `success`, `warn` to stdout, `error` to stderr. Never use them
inside a `$(...)` capture. Plus `log_vars` for the `key: value` block — two-pass,
so a long key like `Shared resource group` aligns rather than breaking.

User-facing messages that scripts also _parse_ — `Loaded .env`, the usage line,
the command-log path — go to **stderr**, so stdout stays clean for captures.

Drop memorywell's `export CLIENT_IP="$(curl -s https://api.ipify.org)"`. It
existed only to open a Postgres firewall, and there is no Postgres — an
unnecessary outbound call on every script run.

## Names are minted lazily

`deployment_name()` and `image_tag()` are **functions**, not assignments done at
source time. This matters: `deploy-all.sh` sources `common.sh` but never
deploys, and `teardown.sh --precheck` never deploys either. An eager name would
overwrite `$LAST_DEPLOYMENT_FILE` on every one of those runs, so the next real
deploy would reuse a stale timestamp and push an image tag that was already
deployed.

Verify: source `common.sh` a few times and confirm no `.deployment` file appears;
only `deployment_name` should create one.

## The `run` family

Every `az`/`curl` call goes through one of three wrappers, which log the command
to `logs/<script>-<timestamp>.log` as `+ az ...`:

| Wrapper           | Use for                                                           |
| ----------------- | ----------------------------------------------------------------- |
| `run`             | normal calls                                                      |
| `run_hide_stderr` | probes where absence is expected (keeps stdout and the `+` trace) |
| `run_quiet`       | pure existence checks                                             |

**Never append `2>/dev/null` to `run`.** That redirects `run` itself and swallows
the trace along with it, losing the record you wanted. Use `run_hide_stderr`.

Also in `common.sh`: `subscription_name()` (explicit `--subscription`, so it never
depends on ambient context), `fetch_deployment_outputs` (polls ARM outputs until
populated), and the `group_exists` / `vault_is_live` / `vault_is_soft_deleted`
probes — which exit non-zero when `az` itself fails, so an outage is never
mistaken for absence.

## Verify

- `bash -n scripts/common.sh` clean.
- `. .env && source scripts/common.sh && echo "$RG_NAME $SHARED_RG_NAME $SHARED_ACR_NAME"`
  prints `rg-oop-dev rg-oop-shared acroop`.
- `source scripts/common.sh` in a shell with no `.env` and no `BASE_NAME` exits
  with the `:?` message — the guard works.
- With `.env` present, it prints `Loaded .env`.
- `DEPLOYMENT_NAME` matches `<base>-<env>-<14 digits>`, and `IMAGE_TAG` is
  `dev-<those digits>`. Run twice: the second run gets a **different** name.
- `REUSE_DEPLOYMENT=1` on a second call reuses the recorded name.
