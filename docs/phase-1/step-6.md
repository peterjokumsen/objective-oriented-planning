# Phase 1 · Step 6 — `scripts/common.sh`

Ported from `~/repos/memorywell/scripts/common.sh` per `AGENTS.md` § Repo rules
— reviewed against the current version, not copied blind. Every resource name
changes from the `memwell` prefix to `oop`; the shape is otherwise what the
deploy and teardown scripts in this repo depend on. Since the original port it
also shrank: the logging backends and the `az` probes moved into `scripts/_log.sh`
and `scripts/_azure.sh`, so this file is only configuration and naming.

It has four jobs: load `.env`, compute names, mint a unique deployment name, and
source those two helpers.

## Sourced, not executed

`common.sh` has **no shebang** and is never run directly — it is sourced by
`deploy.sh`, `deploy-all.sh`, `deploy-shared.sh`, `teardown.sh` and
`check-state.sh`. It declares `# shellcheck shell=bash` as the first line, which
is how it satisfies the `shellcheck --severity=warning` gate with no exclusions
and no `continue-on-error`. (It briefly carried a shebang and a sourced-file
guard instead; the guard was noise once shellcheck ran clean, and the split into
`_`-prefixed helpers settled the shape.)

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
to `logs/<script>-<timestamp>_commands.log` as `+ az ...` (with stdout and stderr
also teed into their own `_stdout` / `_stderr` files, so a probe's hidden stderr
and a `$(...)` capture's output are recoverable after the console scrolled past):

| Wrapper           | Use for                                                           |
| ----------------- | ----------------------------------------------------------------- |
| `run`             | normal calls                                                      |
| `run_hide_stderr` | probes where absence is expected (keeps stdout and the `+` trace) |
| `run_quiet`       | pure existence checks                                             |

**Never append `2>/dev/null` to `run`.** That redirects `run` itself and swallows
the trace along with it, losing the record you wanted. Use `run_hide_stderr`.

The wrappers and the message printers live in `scripts/_log.sh` (which picks
`_log-local.sh` for a TTY or `_log-ghactions.sh` under Actions, so CI gets
`::warning::`/`::error::` annotations, `##` headings and `<details>` blocks on
the run summary, and collapsible groups instead of colour). Under Actions
nothing is an annotation unless something went wrong: `step` becomes a summary
heading, `success`/`info` bullets, `warn`/`error` the annotations. `summary
<markdown>` appends a block verbatim to `$GITHUB_STEP_SUMMARY` (the run summary
page, which is what a human reads first) and echoes it locally.

`scripts/check-logging.sh` drives every printer and every `run*` wrapper through
both backends offline — no `az`, no `.env` — and asserts where each message
lands: the console streams, the three log files, and the summary. It runs in CI
because every one of those splits is easy to break silently, and none of them
shows up anywhere else until a failed run needs reading.

`common.sh` keeps only the `az` helpers: `subscription_name()`
(explicit `--subscription`, so it never depends on ambient context, and cached in
a file because every caller uses it inside a `$(...)` capture),
`fetch_deployment_outputs` (polls ARM outputs until populated), and the
`group_exists` / `vault_is_live` / `vault_is_soft_deleted` probes — which exit
non-zero when `az` itself fails, so an outage is never mistaken for absence — plus
`run_deployment`, which backgrounds a Bicep subscription deployment and
heartbeats `provisioningState` while it runs. `az deployment sub create` prints
nothing until ARM returns (minutes, for the managed environment), so `run` alone
leaves the log frozen on one trace line; `run_deployment` reports elapsed time
and ARM's state every `DEPLOY_POLL_SECONDS` (default 30) and flushes the command's
output at the end without dropping it.

## Verify

- `bash -n scripts/common.sh scripts/_log.sh scripts/_azure.sh` clean.
- `. .env && source scripts/common.sh && echo "$RG_NAME $SHARED_RG_NAME $SHARED_ACR_NAME $VAULT_NAME"`
  prints `rg-oop-dev rg-oop-shared acroop kv-oop-dev`.
- `source scripts/common.sh` in a shell with no `.env` and no `BASE_NAME` exits
  with the `:?` message — the guard works.
- With `.env` present, it prints `debug: Loaded .env`.
- `DEPLOYMENT_NAME` matches `<base>-<env>-<14 digits>`, and `IMAGE_TAG` is
  `dev-<those digits>`. Run twice: the second run gets a **different** name.
- `REUSE_DEPLOYMENT=1` on a second call reuses the recorded name.
