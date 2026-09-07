#!/bin/bash
set -euo pipefail

# Swap /lib/modules inside an existing rootfs.tar for the current
# build/modules-stage (after a kernel/module rebuild), without redoing the
# bootstrap — same mmdebstrap --variant=custom + tar-in trick as
# rerun_gst_hook.sh. Output replaces the input atomically on success.

BSPDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
IN_TAR=${1:-$BSPDIR/build/rootfs.tar}
STAGE="$BSPDIR/build/modules-stage"
OUT_TAR="${IN_TAR%.tar}-newmod.tar"

[ -f "$IN_TAR" ] || { echo "missing $IN_TAR"; exit 1; }
KVER=$(ls "$STAGE/lib/modules" | head -1)
[ -n "$KVER" ] || { echo "empty modules-stage — run make kernel && make modules"; exit 1; }
echo "[INFO] refreshing rootfs modules to $KVER"

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

mmdebstrap \
  --arch=arm64 \
  --mode=auto \
  --variant=custom \
  --skip=update,setup,cleanup/apt \
  --setup-hook="tar-in '$NODEV_TAR' /" \
  --customize-hook="rm -rf \"\$1\"/lib/modules/* && cp -a '$STAGE/lib/modules/$KVER' \"\$1/lib/modules/\" && chroot \"\$1\" depmod -a '$KVER'" \
  resolute \
  "$OUT_TAR" \
  http://ports.ubuntu.com/ubuntu-ports

mv -f "$OUT_TAR" "$IN_TAR"
rm -f "$NODEV_TAR"
echo "[INFO] $IN_TAR now carries modules for $KVER"
