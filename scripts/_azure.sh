# shellcheck shell=bash
# Azure CLI helpers shared by the deploy/teardown/check scripts: subscription
# naming, existence probes and deployment-output polling. Sourced by
# common.sh — never run directly. Requires the logging helpers from _log.sh
# (run, run_hide_stderr, error, warn).

# Display name of the configured subscription (e.g. "My Subscription"), for log
# lines only. Queried lazily (explicit --subscription, so it never depends on
# the current `az account set` context) so sourcing this file stays cheap and
# never fails when logged out.
#
# At most ONE `az account show` per script run, however many times this is
# called: the name is cached in a file rather than a variable because every
# caller uses it inside a `$(...)` capture (log_vars arguments), and a variable
# set in a command substitution is discarded with the subshell. The cache is
# keyed by subscription id and deliberately outlives the run (a display name
# changes rarely, and the alternative is an `az` round-trip per log header);
# pass --refresh after renaming a subscription, or delete the file.
#   subscription_name             cached (queries on first use)
#   subscription_name --refresh   re-query and overwrite the cache
# Export SUBSCRIPTION_NAME to skip the `az` call entirely (CI does not need it).
export SUBSCRIPTION_NAME_FILE="${TMPDIR:-/tmp}/oop-subscription-name-${SUBSCRIPTION_ID}"
subscription_name() {
  local refresh=0
  if [[ "${1:-}" == "--refresh" ]]; then
    refresh=1
  elif [[ -n "${SUBSCRIPTION_NAME:-}" ]]; then
    printf '%s\n' "$SUBSCRIPTION_NAME"
    return 0
  fi
  if [[ "$refresh" -eq 1 || ! -s "$SUBSCRIPTION_NAME_FILE" ]]; then
    local name
    name="$(az account show --subscription "$SUBSCRIPTION_ID" --query name -o tsv 2>/dev/null || true)"
    printf '%s' "${name:-(unknown)}" > "$SUBSCRIPTION_NAME_FILE"
  fi
  printf '%s\n' "$(cat "$SUBSCRIPTION_NAME_FILE")"
}

# fetch_deployment_outputs <deployment-name> <query> <expected-fields> [max-attempts [delay-secs]]:
# Polls `az deployment sub show` until the TSV query returns all
# <expected-fields> non-empty values, then prints them tab-separated.
# Subscription outputs can lag the Succeeded state (ARM eventual
# consistency), and `az -o tsv` drops null columns entirely (a 2-field query
# with one value missing returns just "value"). Array elements may also come
# back newline-separated instead of tab-separated depending on CLI
# version/shape, so the output is flattened to tabs before counting.
# Fails (after dumping properties.outputs) when the outputs never fill in.
# Capture with:
#   OUT="$(fetch_deployment_outputs "$NAME" "<query>" 2)" || exit 1
# No group/endgroup around the retry loop: the calls below run inside the
# capture, and neither backend would show a workflow command from there.
fetch_deployment_outputs() {
  local deployment_name="${1:?usage: fetch_deployment_outputs <deployment-name> <query> <expected-fields> [max-attempts [delay-secs]]}"
  local query="${2:?usage: fetch_deployment_outputs <deployment-name> <query> <expected-fields> [max-attempts [delay-secs]]}"
  local expected_fields="${3:?usage: fetch_deployment_outputs <deployment-name> <query> <expected-fields> [max-attempts [delay-secs]]}"
  local max_attempts="${4:-10}"
  local delay="${5:-10}"
  local attempt=1 out flat has_empty field
  local -a fields
  while true; do
    out="$(run_hide_stderr az deployment sub show --name "$deployment_name" --query "$query" -o tsv || true)"
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
      error "Deployment $deployment_name is missing expected outputs after $max_attempts checks."
      run_hide_stderr az deployment sub show --name "$deployment_name" \
        --query properties.outputs -o json || true
      return 1
    fi
    warn "Attempt $attempt/$max_attempts: outputs not yet available, retrying in ${delay}s..."
    sleep "$delay"
    attempt=$((attempt + 1))
  done
}

# _elapsed_label <seconds>: "45s" or "7m30s". Minutes alone read as "~0 min" for
# the first heartbeat of a quick deployment, which looks like a bug.
_elapsed_label() {
  local total="$1"
  if ((total < 60)); then
    printf '%ds' "$total"
  elif ((total % 60 == 0)); then
    printf '%dm' "$((total / 60))"
  else
    printf '%dm%ds' "$((total / 60))" "$((total % 60))"
  fi
}

# run_deployment <deployment-name> <az deployment sub args...>: runs a Bicep
# subscription deployment while keeping the log alive.
#
# `az deployment sub create` prints absolutely nothing until ARM returns — a
# managed environment alone takes many minutes — so a plain `run` leaves the log
# frozen at the `+ az deployment sub create …` trace for the whole deployment,
# and the first sign of anything (success or failure) arrives all at once at the
# end. This backgrounds the call and polls `deployment sub show` instead, so
# every DEPLOY_POLL_SECONDS (default 30) the log says the deployment is still
# going and what state ARM reports, while the exit status propagates exactly as
# `run` would.
#
# Output handling matches `run`: stdout to the console and the stdout log,
# stderr to the console and the stderr log. Those streams are captured to temp
# files and flushed at the end, because the whole point is that there is nothing
# to show while it runs — nothing is dropped, only deferred.
#
# The state poll is a bare `az` call, unlike every other command here: its trace
# would double the heartbeat noise, and teardown.sh --verify polls the same way.
# Only the poll skips `run`; the deployment itself is logged normally.
#
#   DEPLOY_POLL_SECONDS   heartbeat interval in seconds (default 30)
#
# The heartbeats are `info`, not `debug`: `::debug::` is invisible unless the
# whole job runs with debug logging, which is exactly the "it looks stuck"
# problem being fixed. Under the GitHub backend each one also becomes a summary
# bullet, so a 20-minute deployment adds ~40 bullets to the run summary — raise
# DEPLOY_POLL_SECONDS if that matters. Deploys are run by hand rather than in
# CI (see AGENTS.md), so this is a knob, not a problem in practice.
run_deployment() {
  local deployment_name="${1:?usage: run_deployment <deployment-name> <az deployment sub args...>}"
  shift
  local poll_seconds="${DEPLOY_POLL_SECONDS:-30}"
  local out_file err_file pid rc=0 elapsed=0 state="" is_what_if=0 arg
  for arg in "$@"; do
    if [[ "$arg" == "what-if" ]]; then
      is_what_if=1
    fi
  done

  out_file="$(mktemp "${TMPDIR:-/tmp}/oop-deploy-out.XXXXXX")"
  err_file="$(mktemp "${TMPDIR:-/tmp}/oop-deploy-err.XXXXXX")"

  log_cmd az deployment sub "$@"
  az deployment sub "$@" >"$out_file" 2>"$err_file" &
  pid=$!
  # Ctrl-C must not leave the deployment running after the script is gone. az is
  # in the same process group and gets the signal anyway; this covers the window
  # where the shell would exit first. Restored on the way out, since the trap is
  # global to the shell but this function is not the script's whole job.
  trap 'kill "$pid" 2>/dev/null' INT TERM

  if [[ "$is_what_if" == "1" ]]; then
    info "What-if submitted; no deployment record is created to poll, reporting elapsed time only."
  else
    info "Deployment $deployment_name submitted; polling every ${poll_seconds}s."
  fi
  # `kill -0` is false once the child has been reaped, so this loop ends as soon
  # as az exits, however long or short that took.
  while kill -0 "$pid" 2>/dev/null; do
    sleep "$poll_seconds"
    kill -0 "$pid" 2>/dev/null || break
    elapsed=$((elapsed + poll_seconds))
    if [[ "$is_what_if" == "1" ]]; then
      info "  still running after ~$(_elapsed_label "$elapsed")..."
    else
      state="$(az deployment sub show --name "$deployment_name" \
        --query properties.provisioningState -o tsv 2>/dev/null || true)"
      if [[ -n "$state" ]]; then
        info "  still running after ~$(_elapsed_label "$elapsed") (state: $state)."
      else
        info "  still running after ~$(_elapsed_label "$elapsed") (state: not submitted yet)."
      fi
    fi
  done
  wait "$pid" || rc=$?
  trap - INT TERM

  if [[ -s "$out_file" ]]; then
    if [[ -n "${STDOUT_LOG:-}" ]]; then
      tee -a "$STDOUT_LOG" <"$out_file"
    else
      cat "$out_file"
    fi
  fi
  if [[ -s "$err_file" ]]; then
    if [[ -n "${STDERR_LOG:-}" ]]; then
      cat "$err_file" >>"$STDERR_LOG"
    fi
    cat "$err_file" >&2
  fi
  rm -f "$out_file" "$err_file"

  if ((rc != 0)); then
    error "az deployment sub $deployment_name exited $rc; see its output above."
  fi
  return "$rc"
}

# group_exists <rg-name>: prints `true`/`false`. Exits nonzero (after an
# `error` line) when `az` itself fails or prints something unexpected, so
# callers never mistake an outage for absence. Capture with an explicit guard:
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

# vault_is_live: succeeds when the vault exists (not deleted). Reads $VAULT_NAME.
# Hides the command's stderr: absence is an expected outcome for this probe.
#
# memorywell dropped this one: right after `group delete --no-wait` the vault
# answers neither way, and reading that window as "already purged" is what left a
# vault soft-deleted on the first nightly run here. teardown.sh probes it BEFORE
# the delete and keeps the answer as VAULT_WAS_LIVE, which is what makes the
# post-delete "neither live nor soft-deleted" case decidable. Keep it.
vault_is_live() {
  run_hide_stderr az keyvault show --name "$VAULT_NAME" >/dev/null
}

# vault_is_soft_deleted: succeeds when a soft-deleted vault of that name is
# waiting for purge. Hides the command's stderr: absence is an expected outcome
# for the probe. (teardown.sh deliberately does not use a "is it live?" probe:
# in the window after `group delete --no-wait` the vault answers neither way.)
vault_is_soft_deleted() {
  run_hide_stderr az keyvault list-deleted --query "[?name=='$VAULT_NAME'].name" -o tsv | grep -q "$VAULT_NAME"
}
