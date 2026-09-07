#!/bin/bash
set -euo pipefail

# Fast iteration on the gst hook WITHOUT redoing the 40-min bootstrap:
# mmdebstrap --variant=custom installs nothing itself; tar-in seeds the
# existing rootfs.tar, the gst hook runs, and a new tarball is written.
# Also usable for any future hook-only fixups.

BSPDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
IN_TAR=${1:-$BSPDIR/build/rootfs.tar}
OUT_TAR=${2:-$BSPDIR/build/rootfs-gst.tar}
[ -f "$IN_TAR" ] || { echo "missing $IN_TAR"; exit 1; }

# tar-in cannot mknod inside the userns — strip /dev nodes first (devtmpfs
# recreates them at boot; mmdebstrap provides its own /dev during hooks).
# GNU tar --delete corrupts large archives; python stream-filter instead.
NODEV_TAR="${IN_TAR%.tar}-nodev.tar"
if [ ! -f "$NODEV_TAR" ] || [ "$IN_TAR" -nt "$NODEV_TAR" ]; then
  echo "[INFO] stripping ./dev from input tar"
  python3 - "$IN_TAR" "$NODEV_TAR" <<'PYEOF'
import sys, tarfile
src, dst = sys.argv[1], sys.argv[2]
with tarfile.open(src, 'r|') as ti, tarfile.open(dst, 'w', format=tarfile.PAX_FORMAT) as to:
    for m in ti:
        if m.name == './dev' or m.name.startswith('./dev/'):
            continue
        to.addfile(m, ti.extractfile(m) if m.isreg() else None)
PYEOF
fi
IN_TAR="$NODEV_TAR"

mmdebstrap \
  --arch=arm64 \
  --mode=auto \
  --variant=custom \
  --skip=update,setup,cleanup/apt \
  --setup-hook="tar-in '$IN_TAR' /" \
  --customize-hook="bash '$BSPDIR/tools/build_gst_plugins.sh' \"\$1\"" \
  resolute \
  "$OUT_TAR" \
  http://ports.ubuntu.com/ubuntu-ports

echo "[INFO] updated rootfs: $OUT_TAR"
