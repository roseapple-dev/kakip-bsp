#!/bin/bash
set -euo pipefail

# Build the AI SDK kernel 6.1.141-cip43 straight from the roseapple fork with
# in-tree kakip_defconfig. All AI SDK patches are baked into the fork as
# commits (no build-time patching); see kernel.mk.

BSPDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$BSPDIR/src/linux"
OUT="$BSPDIR/build/kernel"
STAGE="$BSPDIR/build/modules-stage"
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-   # pinned: do NOT inherit env (bit us once)
J=$(nproc)

[ -d "$SRC" ] || { echo "run 'make fetch' first"; exit 1; }
mkdir -p "$OUT"

# No build-time kernel patches: every AI SDK patch is baked into the roseapple
# fork (kernel.mk), so we build straight from the fetched tree.

# Kakip config is maintained in-tree on the fork as
# arch/arm64/configs/kakip_defconfig (AI SDK RZ/V2H base +
# FRAMEBUFFER_CONSOLE/DETECT_PRIMARY for the HDMI text console + DRM_UDL=m
# for the USB3-HDMI survey). To update it: tweak with menuconfig/scripts/config
# then `make O=$OUT savedefconfig` and copy $OUT/defconfig over kakip_defconfig.
make -C "$SRC" O="$OUT" kakip_defconfig
make -C "$SRC" O="$OUT" -j"$J" Image dtbs modules

rm -rf "$STAGE" && mkdir -p "$STAGE"
make -C "$SRC" O="$OUT" INSTALL_MOD_PATH="$STAGE" modules_install

echo "[INFO] Image: $OUT/arch/arm64/boot/Image"
ls "$OUT"/arch/arm64/boot/dts/renesas/r9a09g057h44-rzv2h-evk*.dtb 2>/dev/null || true
echo "[INFO] modules staged in $STAGE (run tools/build_modules.sh next)"
