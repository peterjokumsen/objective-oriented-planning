#!/usr/bin/env bash
# Check provisioning state of every resource deployed by the Bicep templates.
# Read-only: runs every probe first (each `step`/`+` line goes to stderr), then
# presents one consolidated report using the standard step/info/success/warn/
# error helpers, colour-coded per state — plain text locally, GitHub Actions
# workflow commands under CI (see _log.sh). Exits 0 when everything is
# Succeeded (or nothing is deployed yet), 1 when anything is missing a
# Succeeded state.
#
#   ./scripts/check-state.sh                    full report, writes logs/
#   ./scripts/check-state.sh --rg <name>        single-group report, no logs
#   ... --rg <name> --summary                   + markdown for the run summary
#
# With no --rg the scope is *every* resource group belonging to $BASE_NAME
# (rg-<base>-*), discovered from the subscription rather than assumed from
# $ENVIRONMENT. That matters once a second environment exists: a report that
# only ever looks at rg-<base>-$ENVIRONMENT and rg-<base>-shared silently omits
# a staging group that is burning money. --env-only / --shared-only narrow it
# back to the two names common.sh derives, which is what you want mid-sequence
# (after deploy-shared.sh, before deploy.sh).
#
# --rg mode exists for `teardown.sh --verify`, which reports on one resource
# group while it drains: it prints nothing but the group's
# provisioning state and its resources' states, keeps the `+ az ...` traces off
# the console (TRACE_COMMANDS=0) and writes no log files, and encodes the
# answer in the exit code so the caller does not have to parse the report:
#   0  group absent — gone, or never created
#   1  present, but something is not Succeeded
#   2  present and everything Succeeded
#   64 usage error (never collides with a verdict)
set -euo pipefail

# prepare environment variables
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage() {
  cat <<EOF
Usage: $0 [--env-only] [--shared-only] [--rg <resource-group>] [--summary]

  (no --rg)             check every resource group belonging to \$BASE_NAME
                        (rg-<base>-*), discovered from the subscription.
  --env-only            check only rg-<base>-\$ENVIRONMENT
  --shared-only         check only rg-<base>-shared
  --rg <name>           report one resource group: its provisioning state and
                        its resources' states, nothing else. No command traces,
                        no log files; exit code 0=absent, 1=not Succeeded,
                        2=all Succeeded (see the header comment).
                        An empty value (--rg=) warns and falls back to the
                        default scope rather than narrowing the report to
                        nothing.
  --summary             --rg only: also append the report as a markdown block
                        to \$GITHUB_STEP_SUMMARY (workflow run summary).
                        Does nothing outside a workflow run.
EOF
}

# Usage: check-state.sh [--env-only] [--shared-only] [--rg <name>] [--summary]
#   Default checks every rg-<base>* group in the subscription. --env-only /
#   --shared-only narrow it to one side (e.g. --shared-only after
#   deploy-shared.sh, --env-only after deploy.sh).
#   --rg reports a single, named group instead (see usage above).
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
CHECK_ENV=1
CHECK_SHARED=1
RG_ONLY=""
RG_SEEN=0
SUMMARY=0
while [[ $# -gt 0 ]]; do
  arg="$1"
  case "$arg" in
    --env-only) CHECK_SHARED=0 ;;
    --shared-only) CHECK_ENV=0 ;;
    --summary) SUMMARY=1 ;;
    --rg)
      [[ $# -ge 2 ]] || {
        error "--rg needs a resource group name"
        usage >&2
        exit 64 # EX_USAGE: never collide with the 0/1/2 verdict codes
      }
      RG_ONLY="$2"
      RG_SEEN=1
      shift
      ;;
    --rg=*)
      RG_ONLY="${arg#--rg=}"
      RG_SEEN=1
      ;;
    *)
      error "Unknown argument: $arg"
      usage >&2
      exit 64
      ;;
  esac
  shift
done

# `--rg=` with nothing after it is a typo, not a request for an empty scope, and
# silently reporting nothing is the worst possible answer to it — so say what
# happened and fall back to the full scope. RG_SEEN rather than ${RG_ONLY+x}:
# RG_ONLY is always assigned above, so the expansion test is always true.
if [[ "$RG_SEEN" -eq 1 && -z "$RG_ONLY" ]]; then
  warn "--rg needs a resource group name; falling back to every rg-${BASE_NAME}-* group."
  RG_SEEN=0
fi
# --rg names the group, so the env/shared selectors would just be ignored:
# say so rather than quietly dropping one of them.
if [[ -n "$RG_ONLY" && ( "$CHECK_ENV" -eq 0 || "$CHECK_SHARED" -eq 0 ) ]]; then
  error "--rg cannot be combined with --env-only or --shared-only"
  usage >&2
  exit 64
fi
if [[ "$SUMMARY" -eq 1 && -z "$RG_ONLY" ]]; then
  error "--summary only applies to --rg"
  usage >&2
  exit 64
fi

# In --rg mode the report is the product, so the probes stay quiet: no command
# traces, no command log. The subscription context still has to be explicit
# (this script may run where `az account set` was never called), but its
# narration is skipped. Both before the first `run` below.
if [[ -n "$RG_ONLY" ]]; then
  export TRACE_COMMANDS=0
  run az account set --subscription "$SUBSCRIPTION_ID"
else
  init_command_log "check-state"
  step "Setting subscription..."
  run az account set --subscription "$SUBSCRIPTION_ID"
fi

OVERALL=0

# Indented report helpers: the plain common.sh printers take a ready-made
# message, so prefixing with two spaces keeps report lines visually nested
# under their `step` heading (including in logs, where colour is off).
p_step()    { step "  $*"; }
p_info()    { info "  $*"; }
p_success() { success "  $*"; }
p_warn()    { warn "  $*"; }
p_error()   { error "  $*"; }

# report_state <state> <message>: prints <message> through the helper matching
# <state>, so a failed deployment reads red and a succeeded one green instead of
# every line looking the same.
report_state() {
  local state="$1" message="$2"
  case "$state" in
    Succeeded) p_success "$message" ;;
    Failed | Canceled) p_error "$message" ;;
    absent) p_info "$message" ;;
    n/a) p_info "$message" ;;
    *) p_warn "$message" ;;
  esac
}

# Collected results, keyed by group label ("environment" / "shared").
declare -A GROUP_RG_STATE
declare -A GROUP_RES_TEXT
declare -A GROUP_DEP_TEXT

# collect_group <rg-name> <label> [with-deployments=1]: collects the RG state,
# the per-resource provisioningState (fetched individually with `az resource
# show`, since the list embedding is not authoritative for every type) and —
# unless with-deployments=0 — the latest RG-scope deployments into
# GROUP_RG_STATE / GROUP_RES_TEXT / GROUP_DEP_TEXT, folding anything unhealthy
# into OVERALL. It prints nothing: check_group narrates the probes, and `--rg`
# mode reuses it silently.
# `az resource list` keeps this generic: new Bicep modules show up with no
# script change. Resources without a provisioningState field (e.g. role
# assignments, managed identities) report n/a and are excluded from the health
# check.
#
# The state query uses the CLI's null-coalescing `||`: `properties.provisioningState`
# is the canonical ARM location (ACR, Key Vault, Log Analytics, Container Apps,
# managed environments all use it), while a handful of legacy/older types only
# expose the top-level `provisioningState`. The fallback covers both in one call,
# and still yields empty output — reported as n/a — when neither exists.
#
# A group that `az group show` cannot resolve is recorded as "absent", never as
# a failure: the same call fails both for "no such group" and for a genuine
# API/auth problem, and the teardown poll needs "gone" to read as success. A
# caller that must tell those apart has to ask `az group list` itself.
collect_group() {
  local rg="$1"
  local label="$2"
  local with_deployments="${3:-1}"
  local rg_state entries id name state bad=0

  if ! rg_state=$(run_hide_stderr az group show --name "$rg" --query properties.provisioningState -o tsv); then
    GROUP_RG_STATE[$label]="absent"
    GROUP_RES_TEXT[$label]=""
    GROUP_DEP_TEXT[$label]=""
    return 0
  fi
  GROUP_RG_STATE[$label]="$rg_state"

  if ! entries=$(run az resource list --resource-group "$rg" --query "sort_by(@, &name)[].{n:name, i:id}" -o tsv); then
    OVERALL=1
    GROUP_RES_TEXT[$label]="could not list resources in $rg"
  elif [[ -z "$entries" ]]; then
    GROUP_RES_TEXT[$label]="(no resources)"
  else
    local res_text=""
    while IFS=$'\t' read -r name id; do
      [[ -z "$name" ]] && continue
      state=$(run_hide_stderr az resource show --ids "$id" \
        --query "properties.provisioningState || provisioningState" -o tsv || true)
      # `||` yields empty when the type has neither field; older CLI versions
      # can also print a bare None for a scalar null, so normalise both to n/a
      # rather than reporting a bogus non-Succeeded state.
      state="${state:-n/a}"
      [[ "$state" == "None" || "$state" == "null" ]] && state="n/a"
      [[ -z "$res_text" ]] || res_text="$res_text"$'\n'
      res_text="$res_text$name"$'\t'"$state"
      if [[ "$state" != "Succeeded" && "$state" != "n/a" ]]; then
        bad=1
      fi
    done <<< "$entries"
    [[ "$bad" -eq 0 ]] || OVERALL=1
    GROUP_RES_TEXT[$label]="$res_text"
  fi

  # Deployments are not part of the --rg report, and a failed one would flip
  # OVERALL for something that report never mentions — so skip the listing
  # entirely there (one `az` call cheaper per poll).
  if [[ "$with_deployments" != "1" ]]; then
    return 0
  fi

  if deploy_rows=$(run az deployment group list --resource-group "$rg" \
      --query "sort_by(@, &properties.timestamp)[].{n:name, t:properties.timestamp, s:properties.provisioningState}" \
      -o tsv | tail -n 3); then
    local dep_text="" latest=""
    while IFS=$'\t' read -r name timestamp state; do
      [[ -z "$name" ]] && continue
      state="${state:-unknown}"
      [[ -z "$dep_text" ]] || dep_text="$dep_text"$'\n'
      dep_text="$dep_text$name"$'\t'"$timestamp"$'\t'"$state"
      latest="$state"
    done <<< "$deploy_rows"
    # A failed latest run fails the check even when the live resources still
    # look healthy.
    [[ -z "$latest" || "$latest" == "Succeeded" ]] || OVERALL=1
    GROUP_DEP_TEXT[$label]="$dep_text"
  else
    OVERALL=1
    GROUP_DEP_TEXT[$label]="could not list deployments in $rg"
  fi
}

# check_group <rg-name> <label>: the narrated wrapper around collect_group.
check_group() {
  local rg="$1" label="$2"

  # Grouped so the per-resource `az resource show` probe storm collapses into
  # one section in CI. Close the group on every path, and keep the calls at top
  # level: an unclosed group swallows the rest of the step's output.
  group "Collecting state for $rg ($label)"
  step "Checking resource group $rg ($label)..."
  collect_group "$rg" "$label"
  step "Fetching latest deployments in $rg ($label)..."
  endgroup
}

# fetch_sub_deployments <name-prefix>: stores the latest 3 subscription
# deployments whose name starts with <name-prefix> in the global SUB_ROWS and
# folds the newest one's state into OVERALL. Returns 1 only when the listing
# itself failed; an empty result is a valid "nothing deployed yet" answer and
# must stay green.
fetch_sub_deployments() {
  local prefix="$1"
  local latest
  if ! sub_rows=$(run az deployment sub list \
      --query "sort_by(@, &properties.timestamp)[?starts_with(name, '${prefix}')].{n:name, t:properties.timestamp, s:properties.provisioningState}" \
      -o tsv | tail -n 3); then
    OVERALL=1
    SUB_ROWS=""
    return 1
  fi
  SUB_ROWS="$sub_rows"
  if [[ -n "$sub_rows" ]]; then
    latest="$(printf '%s\n' "$sub_rows" | tail -n 1 | cut -f3)"
    [[ -z "$latest" || "$latest" == "Succeeded" ]] || OVERALL=1
  fi
  return 0
}

# report_rows <block> <deployment-rows>: prints one collected block as indented
# report lines. A block is either empty ("nothing to show"), an informational
# marker set by check_group ("(no resources)"), a failure marker ("could not
# list ..."), or tab-separated rows (name + state, or name + timestamp + state
# when <deployment-rows> is 1). Only real rows go through report_state, so
# markers never pick up a state colour.
report_rows() {
  local block="$1"
  local name timestamp state
  case "$block" in
    "" | "(none)") p_info "(none)" ;;
    "(no resources)") p_info "$block" ;;
    "could not list"*) p_error "$block" ;;
    *)
      if [[ "$2" == "1" ]]; then
        # name, timestamp, state
        while IFS=$'\t' read -r name timestamp state; do
          [[ -z "$name" ]] && continue
          report_state "${state:-unknown}" "$name ($timestamp): ${state:-unknown}"
        done <<< "$block"
      else
        # name, state
        while IFS=$'\t' read -r name state; do
          [[ -z "$name" ]] && continue
          report_state "${state:-unknown}" "$name: ${state:-unknown}"
        done <<< "$block"
      fi
      ;;
  esac
}

# report_single_rg <rg-name>: the `--rg` report — the group's provisioning
# state and its resources' states, and nothing else (no deployments, no
# subscription header). An absent group is the one case with no resource list,
# since there is nothing left to enumerate.
report_single_rg() {
  local rg_name="$1"
  local rg_state="${GROUP_RG_STATE[target]:-unknown}"

  step "Resource group $rg_name"
  if [[ "$rg_state" == "absent" ]]; then
    info "not found (deleted or never created)"
    return 0
  fi
  report_state "$rg_state" "provisioningState: $rg_state"
  p_step "Resources:"
  report_rows "${GROUP_RES_TEXT[target]:-}" 0
}

# summarise_single_rg <rg-name>: the same facts as report_single_rg, as a
# markdown block for the workflow run summary. Built from the collected values,
# not scraped from the console output, so it stays correct whatever the backend
# does to the text. No-op unless running on a runner (no $GITHUB_STEP_SUMMARY).
# Resource names and states are ARM-controlled (letters, digits, dashes), so
# nothing needs escaping for the table to render.
summarise_single_rg() {
  local rg_name="$1"
  local rg_state="${GROUP_RG_STATE[target]:-unknown}"
  local block="" name state

  # Leading blank line: consecutive blocks (one per poll) need separating, or
  # the next heading is absorbed into the previous table.
  if [[ "$rg_state" == "absent" ]]; then
    summary ""
    summary "### ${rg_name} — gone (deleted or never created)"
    return 0
  fi

  block=""
  block+="### ${rg_name} at $(date -u +%H:%M:%S) UTC"
  block+=$'\n\n'
  block+="| Resource | State |"$'\n'
  block+="| --- | --- |"
  block+=$'\n'
  block+="| _resource group_ | ${rg_state} |"
  while IFS=$'\t' read -r name state; do
    [[ -z "$name" ]] && continue
    block+=$'\n'
    block+="| ${name} | ${state:-unknown} |"
  done <<< "${GROUP_RES_TEXT[target]:-}"
  summary "$block"
}

# report_group <label> <rg-name>: prints one group's collected results.
report_group() {
  local label="$1"
  local rg_name="$2"
  local rg_state="${GROUP_RG_STATE[$label]:-unknown}"

  step "Resource group $rg_name ($label)"
  report_state "$rg_state" "provisioningState: $rg_state"

  p_step "Resources:"
  report_rows "${GROUP_RES_TEXT[$label]:-}" 0

  p_step "Latest deployments:"
  report_rows "${GROUP_DEP_TEXT[$label]:-}" 1
}

# report_sub_deployments <label> <rows> <ok>: prints the collected
# subscription-scope deployments for <label> ("environment" / "shared"). <ok> is
# 0 when the listing itself failed; empty <rows> just means nothing deployed yet.
report_sub_deployments() {
  local label="$1"
  local rows="$2"
  local ok="$3"

  step "Subscription deployments ($label)"
  if [[ "$ok" != "1" ]]; then
    p_error "could not list $label subscription deployments (see above)"
    return 0
  fi
  report_rows "$rows" 1
}

# Single-group mode: report and answer, with the exit code carrying the verdict
# (0 gone, 1 not Succeeded, 2 all Succeeded). No subscription name lookup, no
# deployment listings, no command log — the teardown Verify step polls this
# every few minutes and only wants the one group's state.
if [[ -n "$RG_ONLY" ]]; then
  collect_group "$RG_ONLY" "target" 0
  report_single_rg "$RG_ONLY"
  if [[ "$SUMMARY" -eq 1 ]]; then
    summarise_single_rg "$RG_ONLY"
  fi
  if [[ "${GROUP_RG_STATE[target]:-}" == "absent" ]]; then
    exit 0
  fi
  [[ "$OVERALL" -eq 0 ]] && exit 2
  exit 1
fi

# Resolved once and reused in both headers below: it is an `az account show`
# round-trip, and every caller only wants it for the log line.
SUB_NAME="$(subscription_name)"

# --- scope: which groups this report covers -----------------------------------
#
# RG_NAMES / GROUP_LABELS are parallel arrays; the label is the group name with
# the rg-<base>- prefix stripped, which is also the middle segment of every
# deployment name for it (<base>-<label>-<timestamp>) — so one value drives the
# report heading, the sub-deployment prefix and the summary.
#
# Not called GROUPS: bash treats that as the read-only built-in holding the
# current user's group IDs, so an assignment to it is silently dropped and the
# count comes back as the user's group count instead of the resource groups.
RG_NAMES=()
GROUP_LABELS=()

add_group() {
  local name="$1" label="${1#rg-${BASE_NAME}-}"
  RG_NAMES+=("$name")
  GROUP_LABELS+=("$label")
}

# discover_groups: every resource group in the subscription that belongs to this
# BASE_NAME, so a second environment is covered instead of silently omitted.
#
# Two different empty answers are separated on purpose. A *failed* listing is an
# outage or a bad credential, and falling back to the derived names (reported as
# absent) would present that as "everything is deleted" — the most dangerous
# possible reading. So a failure falls back with a warning, while a successful
# listing that simply found nothing reports the derived names as absent, which is
# the true answer.
discover_groups() {
  local ok=1 names="" name
  names="$(run_hide_stderr az group list \
    --query "[?starts_with(name, 'rg-${BASE_NAME}-')].name" -o tsv)" || ok=0

  if [[ "$ok" -eq 1 && -n "$names" ]]; then
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      add_group "$name"
    done < <(printf '%s\n' "$names" | sort)
    return 0
  fi

  if [[ "$ok" -eq 0 ]]; then
    warn "Could not list resource groups matching rg-${BASE_NAME}-* (see above); checking the two derived names instead."
  else
    info "No resource group matches rg-${BASE_NAME}-*; reporting the derived names as absent."
  fi
  add_group "$RG_NAME"
  add_group "$SHARED_RG_NAME"
}

if [[ "$CHECK_ENV" -eq 0 ]]; then
  add_group "$SHARED_RG_NAME"
  SCOPE_DESC="shared only: $SHARED_RG_NAME"
elif [[ "$CHECK_SHARED" -eq 0 ]]; then
  add_group "$RG_NAME"
  SCOPE_DESC="environment only: $RG_NAME"
else
  step "Discovering resource groups matching rg-${BASE_NAME}-*..."
  discover_groups
  SCOPE_DESC="every rg-${BASE_NAME}-* group in the subscription"
fi

GROUP_COUNT="${#RG_NAMES[@]}"
log_vars \
  "Subscription=$SUB_NAME ($SUBSCRIPTION_ID)" \
  "Resource group=$RG_NAME" \
  "Shared resource group=$SHARED_RG_NAME" \
  "Scope=$SCOPE_DESC" \
  "Groups in scope=$GROUP_COUNT"

# SUB_ROWS_BY_GROUP / SUB_OK_BY_GROUP hold each group's subscription-scope
# deployment rows, keyed by group name: the listing is per-name-prefix, so N
# groups mean N calls and N results to report.
declare -A SUB_ROWS_BY_GROUP SUB_OK_BY_GROUP

for i in "${!RG_NAMES[@]}"; do
  rg_name="${RG_NAMES[$i]}"
  label="${GROUP_LABELS[$i]}"

  check_group "$rg_name" "$label"

  step "Fetching ${label} subscription deployments..."
  if fetch_sub_deployments "${BASE_NAME}-${label}-"; then
    SUB_ROWS_BY_GROUP["$rg_name"]="$SUB_ROWS"
    SUB_OK_BY_GROUP["$rg_name"]=1
  else
    SUB_ROWS_BY_GROUP["$rg_name"]=""
    SUB_OK_BY_GROUP["$rg_name"]=0
  fi
done

# ---------------------------------------------------------------- report ----

success "Information collection completed."
echo ""
step "Report"
# The per-resource report lines are long and only interesting when something is
# wrong, so the whole phase is one collapsible section in CI. The summary below
# stays outside it and must remain the last thing printed.
group "Report"
log_vars \
  "Subscription=$SUB_NAME ($SUBSCRIPTION_ID)" \
  "Scope=$SCOPE_DESC" \
  "Groups in scope=$GROUP_COUNT" \
  "Environment=${ENVIRONMENT}"

for i in "${!RG_NAMES[@]}"; do
  rg_name="${RG_NAMES[$i]}"
  label="${GROUP_LABELS[$i]}"
  report_group "$label" "$rg_name"
  report_sub_deployments "$label" \
    "${SUB_ROWS_BY_GROUP[$rg_name]:-}" "${SUB_OK_BY_GROUP[$rg_name]:-1}"
done
endgroup

step "Summary"
if [[ "$OVERALL" == "0" ]]; then
  success "Check complete: everything Succeeded."
else
  error "Check complete: something is not Succeeded (see above)."
fi
exit "$OVERALL"
