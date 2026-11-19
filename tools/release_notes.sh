#!/bin/bash
set -euo pipefail

# Write the release notes: BSP version (git describe on the v* tags) plus the
# HEAD of the BSP and of every repo fetched into src/.
#
# Usage: release_notes.sh [output-file]

BSPDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC=${SRC:-$BSPDIR/src}
OUT=${1:-$BSPDIR/build/release_notes.txt}

g() { git -c safe.directory='*' -C "$@"; }

mkdir -p "$(dirname "$OUT")"
{
  echo "kakip-bsp $(g "$BSPDIR" describe --tags --match 'v[0-9]*' --always --dirty)"
  echo "generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  for d in "$BSPDIR" "$SRC"/*/; do
    [ -e "$d/.git" ] || continue
    dirty=
    [ -z "$(g "$d" status --porcelain --untracked-files=no)" ] || dirty=' (dirty)'
    printf '%-20s %s%s\n' "$(basename "$d")" "$(g "$d" rev-parse HEAD)" "$dirty"
  done
} > "$OUT"
cat "$OUT"
