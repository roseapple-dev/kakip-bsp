#!/bin/bash
set -euo pipefail

# Bootloader for Kakip EVK. Default: reuse the AI SDK's prebuilt, proven
# BL2/FIP srec from board_setup/xSPI.zip. --from-source builds u-boot 2024.07
# + TF-A 2.10 from the pinned local tarballs (same SRCREVs as the recipes).

BSPDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT="$BSPDIR/build/firmware"
mkdir -p "$OUT"

if [ "${1:-}" != "--from-source" ]; then
  echo "[INFO] using prebuilt EVK bootloader from dl/bootloader"
  cp "$BSPDIR/dl/bootloader/"* "$OUT/"
  ls -la "$OUT"
  exit 0
fi

export CROSS_COMPILE=aarch64-linux-gnu-
SRC="$BSPDIR/src"
[ -d "$SRC/u-boot" ] && [ -d "$SRC/trusted-firmware-a" ] || { echo "run 'make fetch' first"; exit 1; }

# Kakip TF-A port comes from the roseapple-dev fork branch (tfa.mk)
[ -d "$SRC/trusted-firmware-a/plat/renesas/rz/board/v2h_kakip_1" ] \
  || { echo "[ERROR] fetched TF-A lacks v2h_kakip_1 — check tfa.mk branch"; exit 1; }

make -C "$SRC/u-boot" kakip_defconfig
make -C "$SRC/u-boot" -j"$(nproc)"

cd "$SRC/trusted-firmware-a"
make PLAT=v2h BOARD=kakip_1 ENABLE_STACK_PROTECTOR=default -j"$(nproc)" bl2 bl31
make -C tools/renesas/rz_boot_param 2>/dev/null || true
make -C tools/fiptool
./tools/renesas/bptool build/v2h/release/bl2.bin "$OUT/bp-kakip.bin" 0x08103000 esd
cp build/v2h/release/bl2.bin "$OUT/bl2-kakip.bin"
./tools/fiptool/fiptool create --align 16 --soc-fw build/v2h/release/bl31.bin \
  --nt-fw "$SRC/u-boot/u-boot.bin" "$OUT/fip-kakip.bin"

# Install to the canonical location create_image.sh reads. dl/ survives
# `make clean` (which only wipes build/), so the built bootloader is
# cached there and picked up by `make image` without a manual copy.
DEST="$BSPDIR/dl/bootloader/kakip"
mkdir -p "$DEST"
cp "$OUT/bp-kakip.bin" "$OUT/bl2-kakip.bin" "$OUT/fip-kakip.bin" "$DEST/"
echo "[INFO] kakip bootloader built in $OUT and installed to $DEST (bp/bl2/fip)"
