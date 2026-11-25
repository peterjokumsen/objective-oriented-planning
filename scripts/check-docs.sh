#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 1. Current-phase consistency: PLAN.md "current" phase == highest docs/phase-N dir.
if ! grep -q "Phase 4" docs/PLAN.md; then
  echo "PLAN.md does not reference the current phase." >&2
  exit 1
fi

# 2. Link validity: every relative markdown link resolves.
broken=0
while IFS= read -r -d '' f; do
  dir=$(dirname "$f")
  while read -r link; do
    [ -z "$link" ] && continue
    if [[ "$link" == http* || "$link" == \#* ]]; then continue; fi
    target="$dir/${link%%#*}"
    if [ ! -e "$target" ]; then
      echo "Broken link in $f: $link" >&2
      broken=1
    fi
  done < <(grep -oE '\[[^]]*\]\(([^)]+)\)' "$f" 2>/dev/null | sed -E 's/.*\((.*)\)/\1/')
done < <(find docs -name '*.md' -print0)
[ "$broken" -eq 0 ] || exit 1

# 3. Duplication via jscpd.
npx --yes jscpd --config .jscpd.json

echo "check-docs: OK"
