#!/usr/bin/env bash
# Full deployment: shared resources first, then the environment.
# Passes the action through to both steps (e.g. `./deploy-all.sh what-if`).
# Fails fast: the environment step never runs if the shared step fails.
#
# Ported from ~/repos/memorywell/scripts/deploy-all.sh. Convenience only --
# deploy.sh already self-heals a missing shared group on `create`, so this is for
# a clean, readable two-phase log rather than for correctness.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging helpers + env (BASE_NAME, ENVIRONMENT, ...). Note this does NOT mint a
# deployment name: common.sh's names are lazy, and deploy-all.sh never calls
# `az deployment sub create` itself.
source "$SCRIPT_DIR/common.sh"

# Validate args before touching Azure (mirrors deploy-shared.sh/deploy.sh).
ACTION="${1:-create}"
if [[ "$ACTION" != "create" && "$ACTION" != "what-if" ]]; then
  error "${1-} is not a valid action"
  echo "Usage: $0 [create|what-if]" >&2
  exit 1
fi

init_command_log "deploy-all"

step "Deploying shared resources..."
if ! run "$SCRIPT_DIR/deploy-shared.sh" "$ACTION"; then
  error "Shared deployment failed; aborting before environment deployment."
  exit 1
fi

step "Deploying environment resources..."
run "$SCRIPT_DIR/deploy.sh" "$ACTION"

success "All deployments completed successfully."
