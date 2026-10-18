#!/usr/bin/env bash
# Compile every Bicep file in infra/ to prove it builds, writing the compiled
# JSON somewhere harmless.
#
# Why not just run `az bicep build --file infra/main.bicep` by hand: without
# `--stdout`, bicep drops a .json file next to its source, so a validation run
# litters infra/ with build artifacts. This script always passes `--stdout` and
# redirects the result into --outdir (default build/bicep), mirroring the
# source tree. infra/ stays source-only.
#
# Usage: validate-bicep.sh [--outdir <dir>] [--skip-params]
#   --outdir <dir>   where to put the compiled JSON (default: build/bicep)
#   --skip-params    validate only *.bicep, not *.bicepparam
#
# Exit codes: 0 all files compile, 1 one or more failed, 64 bad usage.
#
# Compiler: `az bicep` when the Azure CLI is on PATH (the local case, and the
# one that keeps the bicep version in step with `az bicep format` in the
# pre-commit hook), otherwise the standalone `bicep` binary. Note that
# GitHub-hosted runners *do* have `az`, so CI pins BICEP_MODE=bicep to use the
# version it installed rather than whatever the CLI bundles. Override with
# BICEP_MODE=az|bicep.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Printers only (step/info/error/...); no .env, no Azure names — validating
# templates must not depend on being logged in or on a subscription.
# shellcheck source=_log.sh
source "${ROOT}/scripts/_log.sh"

usage() {
  cat <<EOF
Usage: $0 [--outdir <dir>] [--skip-params]

  --outdir <dir>   where to write the compiled JSON (default: build/bicep)
  --skip-params    validate only *.bicep, not *.bicepparam
EOF
}

OUTDIR=""
SKIP_PARAMS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --outdir)
      [[ $# -ge 2 ]] || {
        error "--outdir needs a directory"
        usage >&2
        exit 64
      }
      OUTDIR="$2"
      shift
      ;;
    --outdir=*) OUTDIR="${1#--outdir=}" ;;
    --skip-params) SKIP_PARAMS=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      error "Unknown argument: $1"
      usage >&2
      exit 64
      ;;
  esac
  shift
done

# Resolve the two command shapes up front so the loop below stays readable.
# `az bicep build` takes --file; the standalone CLI takes a positional path.
case "${BICEP_MODE:-auto}" in
  az)
    BICEP_MODE="az" ;;
  bicep)
    BICEP_MODE="bicep" ;;
  auto)
    if command -v az >/dev/null 2>&1; then
      BICEP_MODE="az"
    elif command -v bicep >/dev/null 2>&1; then
      BICEP_MODE="bicep"
    else
      error "Neither 'az' nor 'bicep' is on PATH."
      error "Install one: 'az bicep install' or https://github.com/Azure/bicep/releases"
      exit 1
    fi
    ;;
  *)
    error "Unknown BICEP_MODE: ${BICEP_MODE} (expected auto, az or bicep)"
    exit 64
    ;;
esac

if [[ "$BICEP_MODE" == "az" ]]; then
  info "Compiler: az bicep ($(az bicep version 2>/dev/null | head -1 || echo 'version unknown'))"
else
  info "Compiler: bicep ($(bicep --version 2>/dev/null | head -1 || echo 'version unknown'))"
fi

# build <file>: compile one .bicep, discarding stdout. `--stdout` is the whole
# point — without it bicep writes <file>.json next to the source. Routed
# through `run` so the `+ az bicep build …` trace reaches the command log.
build() {
  local file="$1"
  if [[ "$BICEP_MODE" == "az" ]]; then
    run az bicep build --file "$file" --stdout
  else
    run bicep build "$file" --stdout
  fi
}

# build_params <file>: same for a .bicepparam. These are a separate command in
# both toolchains — `az bicep build` rejects a .bicepparam outright.
build_params() {
  local file="$1"
  if [[ "$BICEP_MODE" == "bicep" ]]; then
    run bicep build-params "$file" --stdout
  else
    run az bicep build-params --file "$file" --stdout
  fi
}

# compile <file> <kind> [suffix]: compile, keep the JSON out of infra/, and put
# it in the mirrored output tree so a failure can be inspected afterwards.
compile() {
  local file="$1" kind="$2" suffix="${3:-}"
  local out="$OUTDIR/${file#infra/}"
  out="${out%.*}$suffix.json"
  mkdir -p "$(dirname "$out")"
  if [[ "$kind" == "params" ]]; then
    build_params "$file" >"$out"
  else
    build "$file" >"$out"
  fi
}

init_command_log "validate-bicep"

OUTDIR="${OUTDIR:-$ROOT/build/bicep}"
if [[ "$OUTDIR" != /* ]]; then
  OUTDIR="$ROOT/$OUTDIR"
fi
info "Output: $OUTDIR"

failures=0
count=0
# find over $ROOT/infra, relative paths kept for readable output; sorted so a
# failure is reproducible run to run. Keep these patterns in sync with the
# bicep-format hook in .pre-commit-config.yaml.
while IFS= read -r file; do
  count=$((count + 1))
  rel="${file#${ROOT}/}"
  # One group per file: a failing template's diagnostics are the only thing
  # worth expanding in CI.
  group "build $rel"
  if compile "$rel" bicep; then
    success "ok $rel"
  else
    error "build failed: $rel"
    failures=$((failures + 1))
  fi
  endgroup
done < <(find "$ROOT/infra" -name '*.bicep' | sort)

if [[ "$SKIP_PARAMS" -eq 0 ]]; then
  while IFS= read -r file; do
    count=$((count + 1))
    rel="${file#${ROOT}/}"
    group "build-params $rel"
    # .parameters.json mirrors bicep's own naming for a compiled .bicepparam.
    if compile "$rel" params ".parameters"; then
      success "ok $rel"
    else
      error "build-params failed: $rel"
      failures=$((failures + 1))
    fi
    endgroup
  done < <(find "$ROOT/infra" -name '*.bicepparam' | sort)
fi

step "Summary"
log_vars \
  "Compiler=$BICEP_MODE" \
  "Files=$count" \
  "Failed=$failures" \
  "Output=$OUTDIR"

if [[ "$failures" -gt 0 ]]; then
  error "$failures of $count file(s) failed to build."
  exit 1
fi
success "All $count file(s) compiled cleanly."
