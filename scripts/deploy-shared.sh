#!/usr/bin/env bash
# One-time (per subscription) shared-resource deployment: the resource group
# holding what every environment shares -- the ACR and the App Configuration
# store.
#
# Ported from ~/repos/memorywell/scripts/deploy-shared.sh and reviewed against it.
set -euo pipefail

# prepare environment variables
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# Validate args before touching Azure.
ACTION="${1:-create}"
if [[ "$ACTION" != "create" && "$ACTION" != "what-if" ]]; then
  error "${1-} is not a valid action"
  echo "Usage: $0 [create|what-if]" >&2
  exit 1
fi

init_command_log "deploy-shared"

# Its own deployment-name file, so a shared run never clobbers the environment
# deployment name (and vice versa). Same reason as common.sh's: subscription
# deployment names must be unique per run.
SHARED_DEPLOYMENT_FILE="${TMPDIR:-/tmp}/oop-${BASE_NAME}-shared.deployment"
if [[ -n "${REUSE_DEPLOYMENT:-}" && -f "$SHARED_DEPLOYMENT_FILE" ]]; then
  SHARED_DEPLOYMENT_NAME="$(cat "$SHARED_DEPLOYMENT_FILE")"
else
  SHARED_DEPLOYMENT_NAME="${BASE_NAME}-shared-$(date -u +%Y%m%d-%H%M%S)"
  printf '%s' "$SHARED_DEPLOYMENT_NAME" > "$SHARED_DEPLOYMENT_FILE"
fi

run az account set --subscription "$SUBSCRIPTION_ID"

# ACR purges are slow, so the shared group can linger in `Deleting` long after a
# teardown with --shared. A Bicep sub-deployment into that window fails partway
# through, so fail fast with the fix instead.
step "Checking shared resource group $SHARED_RG_NAME state..."
if SHARED_RG_STATE=$(run_hide_stderr az group show --name "$SHARED_RG_NAME" --query properties.provisioningState -o tsv); then
  success "Resource group $SHARED_RG_NAME exists (provisioningState: $SHARED_RG_STATE)."
  if [[ "$SHARED_RG_STATE" == "Deleting" ]]; then
    error "Resource group $SHARED_RG_NAME is still deleting (an ACR purge can take minutes)."
    error "Wait until it is gone, then retry. Check with:"
    error "  az group show --name \"$SHARED_RG_NAME\" --query properties.provisioningState -o tsv"
    exit 1
  fi
else
  info "Resource group $SHARED_RG_NAME does not exist (expected on first run)."
  SHARED_RG_STATE="absent"
fi

log_vars \
  "Action=$ACTION" \
  "Subscription=$SUBSCRIPTION_ID" \
  "Shared resource group=$SHARED_RG_NAME" \
  "RG state=$SHARED_RG_STATE" \
  "Registry=$SHARED_ACR_NAME" \
  "Location=$LOCATION" \
  "Deployment=$SHARED_DEPLOYMENT_NAME"

run az deployment sub "$ACTION" \
  --location "$LOCATION" \
  --name "$SHARED_DEPLOYMENT_NAME" \
  --template-file "$ROOT/infra/shared.bicep" \
  --parameters "$ROOT/infra/shared.bicepparam"

if [[ "$ACTION" == "what-if" ]]; then
  success "What-if analysis completed. No changes were made."
  exit 0
fi

# The deployment call above blocks, but the shared group and registry can still
# lag behind (eventual consistency) or report a non-terminal state on a slow run.
# Poll until the deployment reads Succeeded rather than trusting one read.
step "Waiting for shared deployment $SHARED_DEPLOYMENT_NAME to succeed..."
attempt=1
max_attempts=15 # 15 x 60s: ACR + RG propagation can take minutes
while true; do
  SHARED_STATE=$(run_hide_stderr az deployment sub show --name "$SHARED_DEPLOYMENT_NAME" \
    --query properties.provisioningState -o tsv || true)
  if [[ "$SHARED_STATE" == "Succeeded" ]]; then
    success "Shared deployment $SHARED_DEPLOYMENT_NAME succeeded."
    break
  fi
  if [[ "$SHARED_STATE" == "Failed" || "$SHARED_STATE" == "Canceled" ]]; then
    error "Shared deployment $SHARED_DEPLOYMENT_NAME ended with state: $SHARED_STATE."
    run_hide_stderr az deployment sub show --name "$SHARED_DEPLOYMENT_NAME" \
      --query properties.error -o json || true
    exit 1
  fi
  if [[ "$attempt" -ge "$max_attempts" ]]; then
    error "Shared deployment $SHARED_DEPLOYMENT_NAME not Succeeded after $max_attempts checks (last state: ${SHARED_STATE:-unknown})."
    exit 1
  fi
  warn "Attempt $attempt/$max_attempts: state is ${SHARED_STATE:-unknown}, retrying in 60s..."
  sleep 60
  attempt=$((attempt + 1))
done

# Polled: outputs can lag the Succeeded state (see fetch_deployment_outputs).
SHARED_OUTPUTS="$(fetch_deployment_outputs "$SHARED_DEPLOYMENT_NAME" \
  "[properties.outputs.registryName.value, properties.outputs.loginServer.value, properties.outputs.appConfigStoreName.value]" 3)" || exit 1
IFS=$'\t' read -r SHARED_REGISTRY SHARED_LOGIN_SERVER APP_CONFIG_STORE <<< "$SHARED_OUTPUTS" || true

log_vars \
  "REGISTRY=$SHARED_REGISTRY" \
  "LOGIN_SERVER=$SHARED_LOGIN_SERVER" \
  "APP_CONFIG=$APP_CONFIG_STORE"

# Catches a .env BASE_NAME that no longer matches the deployed registry, which
# would otherwise surface much later as a confusing image-pull failure.
if [[ "$(login_server)" != "$SHARED_LOGIN_SERVER" ]]; then
  error "Login server mismatch (expected $(login_server))"
  exit 1
fi

success "Shared resources deployed; registry $SHARED_REGISTRY and config store $APP_CONFIG_STORE are ready."
