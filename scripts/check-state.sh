#!/usr/bin/env bash
# Check provisioning state of every resource deployed by the Bicep templates.
# Read-only: per resource group it lists the resources, fetches each one's
# provisioningState individually, and reports the latest deployments (group scope
# per RG, plus subscription scope filtered to this project's env/shared name
# prefixes). Prints one `name: state` line per resource and one
# `name (timestamp): state` line per deployment.
# Exits 0 when everything is Succeeded (or nothing is deployed yet), 1 when
# anything is missing a Succeeded state.
#
# Ported from ~/repos/memorywell/scripts/check-state.sh. The value is in the
# exit code: this is what a deploy script can call to prove the thing came up,
# and what CI can call to notice drift.
set -euo pipefail

# prepare environment variables
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# Usage: check-state.sh [--env-only] [--shared-only]
#   Default checks both resource groups. Flags limit the check to one side
#   (e.g. --shared-only after deploy-shared.sh, --env-only after deploy.sh).
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: $0 [--env-only] [--shared-only]"
  exit 0
fi
CHECK_ENV=1
CHECK_SHARED=1
for arg in "$@"; do
  case "$arg" in
    --env-only) CHECK_SHARED=0 ;;
    --shared-only) CHECK_ENV=0 ;;
    *)
      error "Unknown argument: $arg"
      echo "Usage: $0 [--env-only] [--shared-only]" >&2
      exit 2
      ;;
  esac
done

init_command_log "check-state"

run az account set --subscription "$SUBSCRIPTION_ID"

OVERALL=0

# check_group <rg-name> <label>: prints the RG state, then one `name: state`
# line per resource -- each state is fetched individually with `az resource show`,
# since the list embedding is not authoritative for every type. Finishes with the
# RG's latest deployments. `az resource list` keeps this generic: new Bicep
# modules show up with no script change. Resources without a provisioningState
# field (e.g. role assignments) report n/a and are excluded from the check.
check_group() {
  local rg="$1"
  local label="$2"
  local rg_state entries id name state bad=0

  step "Resource group $rg ($label)..."
  if rg_state=$(run_hide_stderr az group show --name "$rg" --query properties.provisioningState -o tsv); then
    info "  provisioningState: $rg_state"
    if [[ "$rg_state" != "Succeeded" ]]; then
      # Not necessarily a failure: `Deleting` is the expected state for a group
      # mid-teardown, which takes ~30 min here. It is not healthy either, so it
      # still counts against the verdict rather than passing silently.
      if [[ "$rg_state" == "Deleting" ]]; then
        warn "  group is Deleting -- teardown in progress, not a deployable state."
      else
        warn "  group is $rg_state (expected Succeeded)."
      fi
      OVERALL=1
    fi
  else
    warn "  absent (not deployed yet)"
    return 0
  fi

  step "Resources in $rg:"
  # A failed list is not an empty list: distinguish them or a broken call reads as
  # "nothing to check" and passes.
  if ! entries=$(run az resource list --resource-group "$rg" --query "sort_by(@, &name)[].{n:name, i:id}" -o tsv); then
    warn "Could not list resources in $rg (see above); skipping resource check."
    OVERALL=1
  elif [[ -z "$entries" ]]; then
    info "  (no resources)"
  else
    while IFS=$'\t' read -r name id; do
      [[ -z "$name" ]] && continue
      state=$(run_hide_stderr az resource show --ids "$id" --query provisioningState -o tsv || true)
      state="${state:-n/a}"
      printf '  %s: %s\n' "$name" "$state"
      if [[ "$state" != "Succeeded" && "$state" != "n/a" ]]; then
        bad=1
      fi
    done <<< "$entries"
    if [[ "$bad" == "1" ]]; then
      warn "Non-Succeeded resources in $rg (see above)."
      OVERALL=1
    else
      # Qualified: every resource reporting n/a (see the comment above) makes
      # "all Succeeded" true almost by default, so say what was actually checked.
      success "No resource in $rg reported a non-Succeeded state (n/a types carry no provisioningState)."
    fi
  fi

  step "Latest deployments in $rg:"
  if deploy_rows=$(run az deployment group list --resource-group "$rg" \
      --query "sort_by(@, &properties.timestamp)[].{n:name, t:properties.timestamp, s:properties.provisioningState}" \
      -o tsv | tail -n 3); then
    print_deployment_rows "$deploy_rows" "resource-group $rg"
  else
    warn "Could not list deployments in $rg (see above)."
    OVERALL=1
  fi
}

# print_deployment_rows <tsv-rows> <label>: prints one `name (timestamp): state`
# line per row (rows arrive oldest-first) and folds the newest row's state into
# OVERALL, so a failed latest run fails the check even when the live resources
# still look healthy.
print_deployment_rows() {
  local rows="$1"
  local label="$2"
  local name timestamp state latest=""

  if [[ -z "$rows" ]]; then
    info "  (none)"
    return 0
  fi
  while IFS=$'\t' read -r name timestamp state; do
    [[ -z "$name" ]] && continue
    state="${state:-unknown}"
    printf '  %s (%s): %s\n' "$name" "$timestamp" "$state"
    latest="$state"
  done <<< "$rows"
  if [[ "$latest" != "Succeeded" ]]; then
    warn "Latest $label deployment is not Succeeded."
    OVERALL=1
  fi
}

log_vars \
  "Subscription=$(subscription_name) ($SUBSCRIPTION_ID)" \
  "Resource group=$RG_NAME" \
  "Shared resource group=$SHARED_RG_NAME"

if [[ "$CHECK_ENV" == "1" ]]; then
  check_group "$RG_NAME" "environment"
fi

if [[ "$CHECK_SHARED" == "1" ]]; then
  check_group "$SHARED_RG_NAME" "shared"
fi

if [[ "$CHECK_ENV" == "1" ]]; then
  step "Latest environment subscription deployments..."
  print_deployment_rows \
    "$(run az deployment sub list \
      --query "sort_by(@, &properties.timestamp)[?starts_with(name, '${BASE_NAME}-${ENVIRONMENT}-')].{n:name, t:properties.timestamp, s:properties.provisioningState}" \
      -o tsv | tail -n 3)" \
    "environment"
fi

if [[ "$CHECK_SHARED" == "1" ]]; then
  step "Latest shared subscription deployments..."
  print_deployment_rows \
    "$(run az deployment sub list \
      --query "sort_by(@, &properties.timestamp)[?starts_with(name, '${BASE_NAME}-shared-')].{n:name, t:properties.timestamp, s:properties.provisioningState}" \
      -o tsv | tail -n 3)" \
    "shared"
fi

if [[ "$OVERALL" == "0" ]]; then
  success "Check complete: everything Succeeded."
else
  error "Check complete: something is not Succeeded (see above)."
fi
exit "$OVERALL"
