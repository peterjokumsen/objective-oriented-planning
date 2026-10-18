# shellcheck shell=bash
# Shared configuration and naming for the scripts in this directory: reads
# .env, derives every Azure resource name, and pulls in the utility scripts.
# Sourced by deploy.sh / deploy-all.sh / deploy-shared.sh / teardown.sh /
# check-state.sh — never run directly. No commands are executed here, only
# variable derivation and sourcing.
#
# Ported from ~/repos/memorywell/scripts/common.sh. Differences, all deliberate:
#   - resource names use the `oop` prefix, and both deployment state files are
#     project-scoped so they cannot collide with another project on one machine;
#   - no CLIENT_IP lookup and no Cosmos name/endpoint (it existed only to open a
#     Postgres firewall and to seed a database; neither exists at this phase).
#
# Utilities (all `_`-prefixed, all sourced rather than run):
#   _log.sh    logging backends + log_vars + the command-log helpers (run, …)
#   _azure.sh  az CLI helpers (subscription_name, group_exists, …)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# _log.sh defines step/info/success/warn/error/debug/group/endgroup. Override
# the backend pick with LOG_FORMAT=local|github. Both backends keep chatter off
# stdout, so `X="$(some_helper)"` captures stay data-only. Never call the
# printers inside a $(...) capture in the local backend either: info/step/
# success go to stdout there, and would be captured along with the result.
source "${_SCRIPTS_DIR}/_log.sh"

if [[ -f "$ROOT/.env" ]]; then
  set -o allexport; source "$ROOT/.env"; set +o allexport
  debug "Loaded .env"
fi

: "${BASE_NAME:?set BASE_NAME in .env}"
: "${ENVIRONMENT:=dev}"
: "${LOCATION:?set LOCATION in .env}"
: "${SUBSCRIPTION_ID:?set SUBSCRIPTION_ID in .env}"

# Sourced after the config above: _azure.sh derives its cache path from
# SUBSCRIPTION_ID at source time and its probes read VAULT_NAME at call time.
source "${_SCRIPTS_DIR}/_azure.sh"

# rg-oop-<env>: everything for one environment, and the whole teardown is
# `az group delete` on it.
export RG_NAME="rg-${BASE_NAME}-${ENVIRONMENT}"

# Shared across environments and kept by default on teardown: the ACR and the App
# Configuration store. Rebuilding it would mean re-pushing every image, and it is
# the only always-on cost.
#
# The registry name drops the environment suffix so one ACR serves every
# environment. ACR names are globally unique, so strip hyphens and lowercase.
SHARED_RG_NAME="rg-${BASE_NAME}-shared"
SHARED_ACR_NAME="$(echo "acr${BASE_NAME}" | tr '[:upper:]' '[:lower:]' | tr -d '-')"

# Key Vault name for this environment, and the single source of truth for it:
# deploy.sh/teardown.sh probe the vault by this name, and infra/main.bicepparam
# reads it back through readEnvironmentVariable('VAULT_NAME'), so the template
# never rebuilds the name from baseName/environment. Keep in mind the name is
# globally unique: changing BASE_NAME or ENVIRONMENT changes it, and a
# soft-deleted vault keeps the old name reserved until it is purged.
VAULT_NAME="kv-${BASE_NAME}-${ENVIRONMENT}"

export SHARED_ACR_NAME SHARED_RG_NAME VAULT_NAME

registry_name() { echo "$SHARED_ACR_NAME"; }
login_server() { echo "${SHARED_ACR_NAME}.azurecr.io"; }

# Subscription-deployment names must be unique per `az deployment sub create`
# run: re-using a name overwrites history and can confuse `sub show` output
# lookups. So each deployment gets a timestamped name
# (`<base>-<env>-YYYYmmdd-HHMMSS`), recorded in $LAST_DEPLOYMENT_FILE.
# Set REUSE_DEPLOYMENT=1 to re-run against the previous name (e.g. debugging
# a failed deployment) instead of minting a new one.
#
# Names are minted lazily via `deployment_name` (and `image_tag` below), not
# at source time: merely sourcing this file (e.g. deploy-all.sh, which never
# deploys directly, or teardown.sh --precheck) must not reserve a name in
# $LAST_DEPLOYMENT_FILE.
export LAST_DEPLOYMENT_FILE="${TMPDIR:-/tmp}/oop-${BASE_NAME}-${ENVIRONMENT}.deployment"
deployment_name() {
  if [[ -z "${DEPLOYMENT_NAME:-}" ]]; then
    if [[ -n "${REUSE_DEPLOYMENT:-}" && -f "$LAST_DEPLOYMENT_FILE" ]]; then
      DEPLOYMENT_NAME="$(cat "$LAST_DEPLOYMENT_FILE")"
    else
      DEPLOYMENT_NAME="${BASE_NAME}-${ENVIRONMENT}-$(date -u +%Y%m%d-%H%M%S)"
      printf '%s' "$DEPLOYMENT_NAME" > "$LAST_DEPLOYMENT_FILE"
    fi
    export DEPLOYMENT_NAME
  fi
  printf '%s\n' "$DEPLOYMENT_NAME"
}

# Image tag is derived from the deployment timestamp so every `deploy.sh` run
# pushes a unique tag (`<env>-YYYYmmdd-HHMMSS`). Re-pushing the floating
# `api:<env>` tag alone does not change the Container App template string,
# so Container Apps mints no new revision; a unique tag per run guarantees
# revision 2+ on every `containerapp update`.
image_tag() {
  deployment_name >/dev/null
  local dep="$DEPLOYMENT_NAME"
  printf '%s\n' "${ENVIRONMENT}-${dep##"${BASE_NAME}-${ENVIRONMENT}-"}"
}
