#!/usr/bin/env bash
set -euo pipefail
# Run web + functions locally.
pnpm nx serve web &
(cd bffs/api-bff && func start) &
wait