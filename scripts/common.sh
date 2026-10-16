#!/usr/bin/env bash
# Shared helpers for the scripts in this directory. Sourced, never executed.
#
# Ported from ~/repos/memorywell/scripts/common.sh and reviewed against it rather
# than copied. Differences, all deliberate:
#   - resource names use the `oop` prefix; the deployment state file is
#     project-scoped so it cannot collide with another project on one machine;
#   - a shebang plus a sourced-file guard, so shellcheck runs with no exclusions;
#   - no CLIENT_IP lookup (it existed only to open a Postgres firewall).
#
# Provides: `.env` loading, the resource name scheme, lazily-minted deployment
# names, command logging, and the `run` family of command wrappers.
#
# shellcheck shell=bash
# Return early when sourced rather than executed, so `bash common.sh` is a no-op
# instead of trying to run a file of function definitions.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "common.sh is sourced by the other scripts; not run directly." >&2
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colour helpers: disabled automatically when stdout is not a TTY or NO_COLOR is
# set, so piped and CI output stays plain. Use step/info/success/warn for stdout;
# error goes to stderr. Never use these inside a $(...) capture.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\e[0m'; C_BLUE=$'\e[34m'; C_GREEN=$'\e[32m'
  C_YELLOW=$'\e[33m'; C_RED=$'\e[31m'; C_CYAN=$'\e[36m'
else
  C_RESET=''; C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_CYAN=''
fi
step()    { printf '%b==>%b %s\n' "$C_BLUE" "$C_RESET" "$*"; }
info()    { printf '%b%s%b\n' "$C_CYAN" "$*" "$C_RESET"; }
success() { printf '%b%s%b\n' "$C_GREEN" "$*" "$C_RESET"; }
warn()    { printf '%b%s%b\n' "$C_YELLOW" "$*" "$C_RESET"; }
error()   { printf '%b%s%b\n' "$C_RED" "$*" "$C_RESET" >&2; }

# Everything user-facing goes to stderr (Loaded .env, usage, the command-log
# line). That keeps stdout clean for machine-readable captures.
if [[ -f "$ROOT/.env" ]]; then
  set -o allexport; source "$ROOT/.env"; set +o allexport
  info "Loaded .env" >&2
fi

# Required in .env; ENVIRONMENT is the only one with a default.
: "${BASE_NAME:?set BASE_NAME in .env}"
: "${ENVIRONMENT:=dev}"
: "${LOCATION:?set LOCATION in .env}"
: "${SUBSCRIPTION_ID:?set SUBSCRIPTION_ID in .env}"

# rg-oop-<env>: everything for one environment, and the whole teardown is
# `az group delete` on it.
export RG_NAME="rg-${BASE_NAME}-${ENVIRONMENT}"

# Shared across environments and kept by default on teardown: the ACR and the App
# Configuration store. Rebuilding it would mean re-pushing every image, and it is
# the only always-on cost.
SHARED_RG_NAME="rg-${BASE_NAME}-shared"
export SHARED_RG_NAME

# The registry name drops the environment suffix so one ACR serves every
# environment. ACR names are globally unique, so strip hyphens and lowercase.
SHARED_ACR_NAME="$(echo "acr${BASE_NAME}" | tr '[:upper:]' '[:lower:]' | tr -d '-')"
export SHARED_ACR_NAME

registry_name() { echo "$SHARED_ACR_NAME"; }
login_server() { echo "${SHARED_ACR_NAME}.azurecr.io"; }

# Display name of the configured subscription, for log lines only. Queried lazily
# and with an explicit --subscription, so it never depends on the ambient
# `az account set` context and never fails when logged out.
subscription_name() {
  az account show --subscription "$SUBSCRIPTION_ID" --query name -o tsv 2>/dev/null \
    || echo "(unknown)"
}

# --- deployment naming -------------------------------------------------------
#
# Subscription-deployment names must be unique per `az deployment sub create`:
# re-using a name overwrites that deployment's history and makes later
# `az deployment sub show` lookups ambiguous. So each deployment mints a
# timestamped name and records it, and REUSE_DEPLOYMENT=1 re-runs against the
# previous name when debugging a failed deployment.
#
# Names are minted **lazily**, not at source time: merely sourcing this file must
# not reserve a name. deploy-all.sh sources it but never deploys; teardown.sh
# --precheck never deploys. An eager name would overwrite $LAST_DEPLOYMENT_FILE on
# every one of those, so the next real deploy would reuse a stale timestamp.
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

# The image tag carries the deployment timestamp, so every deploy pushes a unique
# tag. This is what makes "revisions day one" provable: Container Apps mints a new
# revision when the image *string* in the template changes, so re-pushing the
# floating api:<env> tag alone would change nothing.
image_tag() {
  deployment_name >/dev/null
  local dep="$DEPLOYMENT_NAME"
  printf '%s\n' "${ENVIRONMENT}-${dep##"${BASE_NAME}-${ENVIRONMENT}-"}"
}

log_vars() {
  # Two passes so the values align: find the widest "key:" first, then print.
  # A fixed width breaks as soon as a longer key like "Shared resource group"
  # shows up.
  local width=0 kvp key
  for kvp in "$@"; do
    key="${kvp%%=*}:"
    if (( ${#key} > width )); then
      width=${#key}
    fi
  done
  for kvp in "$@"; do
    printf '  %-*s %s\n' "$width" "${kvp%%=*}:" "${kvp#*=}"
  done
}

# --- command logging and execution -------------------------------------------
#
# `init_command_log <name>` creates `$ROOT/logs/<name>-YYYYmmdd-HHMMSS.log` and
# sets COMMAND_LOG. The `run` family echoes the command (`+ az ...`) to stderr,
# appends it to that log, then executes it. Use one of them for **every** `az` /
# `curl` call, including inside `if` conditions and `$(...)` captures.
#
# Logging goes to **stderr** deliberately: that is what lets `X=$(run az ...)`
# capture only the command's own stdout. The payoff is a copy-pasteable transcript
# of every command a run issued, which is what you want when a deployment fails
# 20 minutes in. `logs/` is git-ignored.
#
#   run              full output (stdout + stderr)
#   run_hide_stderr  hide the command's stderr, keep the `+` trace and stdout --
#                    for probes where absence is an expected outcome
#   run_quiet        hide stdout and stderr -- for pure existence checks
#
# Do NOT append `2>/dev/null` to `run`: that redirects `run` itself and swallows
# the `+` trace along with it, which loses exactly the record you wanted.
export COMMAND_LOG="${COMMAND_LOG:-}"
init_command_log() {
  local name="${1:?usage: init_command_log <name>}"
  mkdir -p "$ROOT/logs"
  COMMAND_LOG="$ROOT/logs/${name}-$(date -u +%Y%m%d-%H%M%S).log"
  export COMMAND_LOG
  info "Command log: $COMMAND_LOG" >&2
}

# _join_quoted: shell-quote each arg (%q) so the logged line is copy-pasteable.
_join_quoted() {
  local out="" a piece
  for a in "$@"; do
    piece=$(printf '%q' "$a")
    if [[ -z "$out" ]]; then
      out="$piece"
    else
      out="$out $piece"
    fi
  done
  printf '%s' "$out"
}

log_cmd() {
  local cmd
  cmd=$(_join_quoted "$@")
  printf '+ %s\n' "$cmd" >&2
  if [[ -n "${COMMAND_LOG:-}" ]]; then
    printf '+ %s\n' "$cmd" >> "$COMMAND_LOG"
  fi
}

run() {
  log_cmd "$@"
  "$@"
}

run_hide_stderr() {
  log_cmd "$@"
  "$@" 2>/dev/null
}

run_quiet() {
  log_cmd "$@"
  "$@" >/dev/null 2>&1
}

# --- Azure helpers -----------------------------------------------------------

# fetch_deployment_outputs <deployment-name> <query> <expected-fields> [max-attempts [delay-secs]]:
# Polls `az deployment sub show` until the TSV query returns all <expected-fields>
# non-empty values, then prints them tab-separated.
# Subscription outputs can lag the Succeeded state (ARM eventual consistency), and
# `az -o tsv` drops null columns entirely (a 2-field query with one value missing
# returns just "value"). Array elements may also come back newline-separated
# instead of tab-separated depending on CLI version/shape, so the output is
# flattened to tabs before counting.
# Fails (after dumping properties.outputs) when the outputs never fill in.
# Capture with:
#   OUT="$(fetch_deployment_outputs "$NAME" "<query>" 2)" || exit 1
fetch_deployment_outputs() {
  local dep="${1:?usage: fetch_deployment_outputs <deployment-name> <query> <expected-fields> [max-attempts [delay-secs]]}"
  local query="${2:?usage: fetch_deployment_outputs <deployment-name> <query> <expected-fields> [max-attempts [delay-secs]]}"
  local expected_fields="${3:?usage: fetch_deployment_outputs <deployment-name> <query> <expected-fields> [max-attempts [delay-secs]]}"
  local max_attempts="${4:-10}"
  local delay="${5:-10}"
  local attempt=1 out flat has_empty field
  local -a fields
  while true; do
    out="$(run_hide_stderr az deployment sub show --name "$dep" --query "$query" -o tsv || true)"
    # Flatten: TSV array elements arrive tab- or newline-separated (CLI
    # version/shape dependent); callers always read a single tab-joined row.
    flat="$(printf '%s' "$out" | tr -d '\r' | tr '\n' '\t')"
    if [[ -n "$flat" ]]; then
      has_empty=0
      IFS=$'\t' read -ra fields <<< "$flat" || true
      # az -o tsv drops null columns, so a partial row has fewer fields, not
      # empty ones: require the full column count first.
      if [[ "${#fields[@]}" -ne "$expected_fields" ]]; then
        has_empty=1
      else
        for field in ${fields[@]+"${fields[@]}"}; do
          if [[ -z "$field" ]]; then
            has_empty=1
            break
          fi
        done
        # read -ra drops trailing empty fields, so also reject leading,
        # trailing, or doubled tabs explicitly (empty first/last/middle col).
        if [[ "$flat" == *$'\t\t'* || "$flat" == *$'\t' || "$flat" == $'\t'* ]]; then
          has_empty=1
        fi
      fi
      if [[ "$has_empty" -eq 0 ]]; then
        printf '%s\n' "$flat"
        return 0
      fi
    fi
    if [[ "$attempt" -ge "$max_attempts" ]]; then
      error "Deployment $dep is missing expected outputs after $max_attempts checks."
      run_hide_stderr az deployment sub show --name "$dep" \
        --query properties.outputs -o json || true
      return 1
    fi
    warn "Attempt $attempt/$max_attempts: outputs not yet available, retrying in ${delay}s..." >&2
    sleep "$delay"
    attempt=$((attempt + 1))
  done
}

# group_exists <rg-name>: prints `true`/`false`. Exits nonzero (after an `error`
# line) when `az` itself fails or prints something unexpected, so callers never
# mistake an outage for absence. Capture with an explicit guard:
#   RG_EXISTS="$(group_exists "$RG_NAME")" || exit 1
group_exists() {
  local rg="$1" out
  if ! out=$(run az group exists --name "$rg" -o tsv); then
    error "Could not check whether resource group $rg exists (see above)."
    return 1
  fi
  case "$out" in
    true|false) printf '%s\n' "$out" ;;
    *)
      error "Unexpected 'az group exists' output for $rg: $out"
      return 1
      ;;
  esac
}

# vault_is_live <vault-name>: succeeds when the vault exists (not deleted).
# vault_is_soft_deleted <vault-name>: succeeds when a soft-deleted vault of that
# name is waiting for purge. Both hide the command's stderr: absence is an
# expected outcome for these probes.
vault_is_live() {
  run_hide_stderr az keyvault show --name "$1" >/dev/null
}

vault_is_soft_deleted() {
  run_hide_stderr az keyvault list-deleted --query "[?name=='$1'].name" -o tsv | grep -q "$1"
}
