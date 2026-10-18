#!/usr/bin/env bash
# Cost control. Destroys everything for one environment between study sessions.
#
# Ported from ~/repos/memorywell/scripts/teardown.sh and reviewed against it. The
# two flags it gained are --precheck and --verify, which the nightly workflow in
# .github/workflows/teardown.yml needs: a cheap read-only pre-check so the common
# case costs nothing, and a verification pass so a silent partial teardown cannot
# leak cost unnoticed. Neither exists in the memorywell original. It also keeps
# memorywell's VAULT_PURGE_WAIT_MINUTES knob (default 20 here, not memorywell's
# 10: the wait is bounded by the managed environment drain, measured at 16-30
# min) and reports drain progress through `check-state.sh --rg` rather than
# counting attempts silently.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# prepare environment variables
source "$SCRIPT_DIR/common.sh"

# Usage: teardown.sh [--purge-vault] [--shared] [--precheck] [--verify]
#   --purge-vault  after deleting the RG, wait for the soft-deleted Key Vault to
#                  appear and purge it, so a same-name redeploy is not blocked.
#                  Without the flag only the RG delete runs (fast, async).
#   --shared       also delete the shared resource group (ACR + App Configuration).
#                  Not the default: the shared RG is the only always-on cost and
#                  survives study-session teardowns, so deleting it is opt-in.
#   --precheck     read-only. Report whether there is anything to tear down, then
#                  exit 0. Never deletes. This is what most nightly runs execute.
#   --verify       read-only. Fail if the environment RG still exists or the Key
#                  Vault is still soft-deleted. Exits non-zero on either.
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: $0 [--purge-vault] [--shared] [--precheck] [--verify]"
  exit 0
fi
PURGE_VAULT=0
DELETE_SHARED=0
PRECHECK=0
VERIFY=0
for arg in "$@"; do
  case "$arg" in
    --purge-vault) PURGE_VAULT=1 ;;
    --shared) DELETE_SHARED=1 ;;
    --precheck) PRECHECK=1 ;;
    --verify) VERIFY=1 ;;
    *)
      error "Unknown argument: $arg"
      echo "Usage: $0 [--purge-vault] [--shared] [--precheck] [--verify]" >&2
      exit 1
      ;;
  esac
done

init_command_log "teardown"

run az account set --subscription "$SUBSCRIPTION_ID"

# --- read-only modes ---------------------------------------------------------

# Cheap and safe to run on its own, which is what makes it testable locally
# without deploying anything.
if [[ "$PRECHECK" == "1" ]]; then
  rg_exists="$(group_exists "$RG_NAME")" || exit 1
  vault_deleted=false
  if vault_is_soft_deleted; then
    vault_deleted=true
  fi

  log_vars \
    "Subscription=$(subscription_name) ($SUBSCRIPTION_ID)" \
    "ResourceGroup=$RG_NAME" \
    "ResourceGroupExists=$rg_exists" \
    "KeyVault=$VAULT_NAME" \
    "VaultSoftDeleted=$vault_deleted"

  # When run from GitHub Actions, publish the verdict so later steps can be gated
  # on it. Absent GITHUB_OUTPUT locally, so this is a no-op in normal use.
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    if [[ "$rg_exists" == "true" || "$vault_deleted" == "true" ]]; then
      echo "needs_teardown=true" >> "$GITHUB_OUTPUT"
    else
      echo "needs_teardown=false" >> "$GITHUB_OUTPUT"
    fi
  fi

  if [[ "$rg_exists" == "false" && "$vault_deleted" == "false" ]]; then
    # Exit 0, not 1: nothing to do is the healthy case, and the workflow uses this
    # to skip its destructive step.
    info "Nothing to tear down."
    exit 0
  fi
  [[ "$rg_exists" == "true" ]] && warn "Resource group $RG_NAME exists and would be deleted."
  [[ "$vault_deleted" == "true" ]] && warn "Key Vault $VAULT_NAME is soft-deleted and would be purged."
  exit 0
fi

# Also read-only. A silent partial teardown is the failure worth catching here,
# because the cost it leaks is invisible until the next billing statement.
if [[ "$VERIFY" == "1" ]]; then
  status=0

  # RG deletion is async (--no-wait below) and draining the Container Apps managed
  # environment is genuinely slow: measured at ~30 min for a real teardown of
  # rg-oop-dev. The budget is deliberately generous -- a false "still exists"
  # fails the nightly job on a teardown that is in fact succeeding, which is the
  # failure mode this check exists to avoid. Keep the workflow's timeout-minutes
  # in step with this.
  #
  # RG_VERIFY_WAIT_MINUTES is the one knob: the nightly workflow leaves it at the
  # ~40 min default, a local run can shorten it to get an answer faster.
  verify_wait_minutes="${RG_VERIFY_WAIT_MINUTES:-40}"
  poll_seconds=10
  report_minutes="${RG_REPORT_INTERVAL_MINUTES:-10}"
  max_attempts=$((verify_wait_minutes * 60 / poll_seconds))
  report_every=$((report_minutes * 60 / poll_seconds))
  [[ "$report_every" -ge 1 ]] || report_every=1
  [[ "$max_attempts" -ge 1 ]] || max_attempts=1

  # report_drain: hand the group's current state to `check-state.sh --rg`, which
  # prints the provisioning state and every resource's state and, with
  # --summary, appends the same as a markdown table to the run summary — so the
  # drain reads as a timeline on the summary page instead of only in the log.
  # Progress reporting only: the poll below decides when the group is gone, so a
  # report that cannot be produced (usage error, a broken script, a flaky API) is
  # a warning, never a failed run. `set -e` does not fire inside an `if`, so a
  # non-zero verdict is expected here and must be read, not propagated.
  report_drain() {
    local rc=0
    "${SCRIPT_DIR}/check-state.sh" --rg "$RG_NAME" --summary || rc=$?
    case "$rc" in
      0) info "  $RG_NAME is gone." ;;
      1) warn "  still draining: some resources are not Succeeded." ;;
      2) info "  group exists, everything Succeeded (delete still propagating)." ;;
      *) warn "  check-state.sh --rg exited $rc; no state report this time." ;;
    esac
  }

  started_at="$(date -u +%H:%M:%S)"
  step "Verifying resource group $RG_NAME is gone (up to ~${verify_wait_minutes} min)..."
  group "Waiting for $RG_NAME to be deleted"
  attempt=1
  next_report=1
  rg_outcome="**not checked**"
  while [[ "$attempt" -le "$max_attempts" ]]; do
    RG_STILL_EXISTS="$(group_exists "$RG_NAME")" || {
      endgroup
      status=1
      rg_outcome="**could not check** (az group exists failed)"
      break
    }
    if [[ "$RG_STILL_EXISTS" != "true" ]]; then
      success "Resource group $RG_NAME is gone."
      rg_outcome="deleted (confirmed after ~$((attempt * poll_seconds / 60)) min)"
      break
    fi
    if (( attempt >= next_report )); then
      report_drain
      next_report=$((attempt + report_every))
    fi
    if [[ "$attempt" -eq "$max_attempts" ]]; then
      error "Resource group $RG_NAME still exists after ~${verify_wait_minutes} min."
      rg_outcome="**still exists**"
      status=1
      break
    fi
    if (( attempt % 6 == 0 )); then
      warn "Attempt $attempt/$max_attempts: $RG_NAME still exists, retrying in ${poll_seconds}s..."
    fi
    sleep "$poll_seconds"
    attempt=$((attempt + 1))
  done
  endgroup

  # An un-purged soft-deleted vault blocks the next same-name deploy, so a
  # leftover one fails loudly rather than becoming a confusing deploy error later.
  vault_outcome="not checked"
  if vault_is_soft_deleted; then
    error "Key Vault $VAULT_NAME is still soft-deleted; purge it manually:"
    error "  az keyvault purge --name \"$VAULT_NAME\""
    vault_outcome="**still soft-deleted** (blocks a same-name redeploy)"
    status=1
  else
    success "Key Vault $VAULT_NAME is not soft-deleted."
    vault_outcome="not soft-deleted (a same-name redeploy is unblocked)"
  fi

  # The run summary: one table answering "is this environment gone and can I
  # deploy again?", which is the only question this workflow exists to answer.
  # The per-report tables were appended above by `check-state.sh --summary`.
  verify_outcome="passed"
  if [[ "$status" -ne 0 ]]; then
    verify_outcome="**failed**"
  fi
  summary ""
  summary "## Teardown verify — ${RG_NAME}"
  summary ""
  summary "| Check | Outcome |"
  summary "| --- | --- |"
  summary "| Resource group | ${rg_outcome} |"
  summary "| Key Vault \`${VAULT_NAME}\` | ${vault_outcome} |"
  summary "| Verify step | ${verify_outcome} |"
  summary "| Started | ${started_at} UTC |"

  if [[ "$status" == "0" ]]; then
    success "Verification passed."
  fi
  exit "$status"
fi

# --- destructive path --------------------------------------------------------

log_vars \
  "Subscription=$(subscription_name) ($SUBSCRIPTION_ID)" \
  "Resource group=$RG_NAME" \
  "KeyVault=$VAULT_NAME" \
  "PurgeVault=$PURGE_VAULT" \
  "DeleteShared=$DELETE_SHARED"

step "Groups in subscription $SUBSCRIPTION_ID:"
run az group list --query '[].name' -o tsv

# Environment group first, always. Shared comes later and only on request:
# reversed, a running container app can lose its image pull mid-teardown.
#
# No early exit when the group is absent: the vault purge and the optional
# shared-RG delete below must still run. An earlier version exited 0 here, which
# meant a scheduled run after a previous teardown silently skipped --shared.
step "Deleting resource group $RG_NAME..."
# Probe the vault BEFORE deleting the group. "Neither live nor soft-deleted"
# after the delete is ambiguous: it can mean "already purged by an earlier run"
# or "mid-transition, about to appear in list-deleted". What disambiguates it is
# whether the vault was live when this run started -- if it was, it *must* appear
# and we wait for it; if it was not, there is genuinely nothing to purge.
VAULT_WAS_LIVE=0
if vault_is_live; then
  VAULT_WAS_LIVE=1
fi

ENV_RG_EXISTS="$(group_exists "$RG_NAME")" || exit 1
if [[ "$ENV_RG_EXISTS" == "true" ]]; then
  run az group delete --name "$RG_NAME" --yes --no-wait
else
  info "Resource group $RG_NAME not found; skipping delete."
fi

# Key Vault soft-deletes: once the group is gone the vault lingers in "deleted"
# state and blocks a same-name redeploy. Opt-in via --purge-vault because the RG
# delete is async and the vault may not have reached soft-deleted yet.
#
# Three states, not two: soft-deleted (purge it), live (wait for it to
# soft-delete -- the RG delete is still draining), or neither.
#
# "Neither" is ambiguous and the distinction matters. On a *repeat* run after a
# purge it means there is genuinely nothing to do, and skipping avoids waiting 20
# minutes for a vault that will never arrive. Immediately after issuing an RG
# delete it can mean the opposite: the vault is mid-transition, already gone from
# the live list while `az keyvault list-deleted` has not caught up yet -- observed
# as a 12-second window on the first nightly dispatch, which skipped the purge and
# left the vault soft-deleted (blocking the next same-name deploy) until --verify
# caught it. VAULT_WAS_LIVE (probed before the delete) is what separates them.
if [[ "$PURGE_VAULT" == "1" ]]; then
  if ! vault_is_soft_deleted && ! vault_is_live && [[ "$VAULT_WAS_LIVE" == "0" ]]; then
    # `success`, not `info`: "nothing to purge, and a redeploy is unblocked" is
    # the outcome this run exists to produce, and the GitHub backend puts
    # successes in the workflow summary (see _log-ghactions.sh) while `info`
    # stays closer to the log.
    success "Key Vault $VAULT_NAME not found (neither live nor soft-deleted) and was not live when this run started; nothing to purge."
  else
    if ! vault_is_soft_deleted; then
      # The vault soft-deletes as part of the resource-group deletion, so this
      # wait is bounded by how long the *group* takes to drain -- measured at
      # ~16-30 min here, not the 5 min this originally allowed. A short budget
      # would fail the destroy step on a teardown that is working.
      # VAULT_PURGE_WAIT_MINUTES caps it (default 20). The nightly workflow may
      # lower it so this step cannot eat the job's timeout budget -- --verify
      # already owns the long wait.
      purge_wait_minutes="${VAULT_PURGE_WAIT_MINUTES:-20}"
      max_attempts=$((purge_wait_minutes * 60 / 10))
      [[ "$max_attempts" -ge 1 ]] || max_attempts=1
      step "Waiting for soft-deleted Key Vault $VAULT_NAME (up to ~${purge_wait_minutes} min)..."
      # Grouped so the probe loop collapses into one section in the nightly
      # GitHub Actions log. Close it on every path: an unclosed group swallows
      # the rest of the step's output. Never group around a $(...) capture.
      group "Waiting for $VAULT_NAME to become soft-deleted"
      attempt=1
      while ! vault_is_soft_deleted; do
        if [[ "$attempt" -ge "$max_attempts" ]]; then
          endgroup
          # Loud, not a silent skip: an un-purged vault surfaces much later as a
          # deploy that fails for no visible reason.
          error "Vault $VAULT_NAME not soft-deleted yet; purge skipped. Retry later:"
          error "  az keyvault list-deleted --query \"[?name=='$VAULT_NAME']\" -o table"
          error "  az keyvault purge --name \"$VAULT_NAME\""
          exit 1
        fi
        warn "Attempt $attempt/$max_attempts: not soft-deleted yet, retrying in 10s..."
        sleep 10
        attempt=$((attempt + 1))
      done
      endgroup
    fi
    step "Purging soft-deleted Key Vault $VAULT_NAME..."
    run az keyvault purge --name "$VAULT_NAME"
    success "Environment resource group deleted, vault purged."
  fi
else
  info "Skipping Key Vault purge (pass --purge-vault to purge $VAULT_NAME for same-name redeploy)."
fi

if [[ "$DELETE_SHARED" == "1" ]]; then
  step "Deleting shared resource group $SHARED_RG_NAME..."
  SHARED_RG_EXISTS="$(group_exists "$SHARED_RG_NAME")" || exit 1
  if [[ "$SHARED_RG_EXISTS" == "true" ]]; then
    run az group delete --name "$SHARED_RG_NAME" --yes --no-wait
  else
    info "Shared resource group $SHARED_RG_NAME not found; skipping delete."
  fi
  success "Teardown complete (environment and shared resource groups deleting)."
else
  info "Shared resource group $SHARED_RG_NAME kept (pass --shared to delete it too)."
fi
