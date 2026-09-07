#!/bin/bash
set -euo pipefail

# Out-of-tree kernel modules against the 6.1.141-cip43 build, invoked exactly
# as the Yocto recipes do:
#   mali_kbase.ko  — kernel-module-mali.inc: S=mali_km/drivers/gpu/arm/midgard,
#                    make KDIR=… BUILD=release MALI_PLATFORM_NAME=devicetree
#   uvcs_drv.ko    — kernel-module-uvcs-drv.bb: B=src/makefile (a directory!),
#                    exports UVCS_SRC/UVCS_INC/VCP4_SRC, make KERNELDIR=…
#   mmngr/mmngrbuf/vspm/vspm_if — renesas-rcar drv repos (fetched to src/)
# Staged into build/modules-stage/lib/modules/<ver>/extra/.

BSPDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DLDIR="$BSPDIR/dl"
PATCHROOT="$BSPDIR/patch"
KDIR="$BSPDIR/build/kernel"
STAGE="$BSPDIR/build/modules-stage"
WORK="$BSPDIR/build/oot-modules"
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-   # pinned: do NOT inherit env (bit us once)
J=$(nproc)

[ -f "$KDIR/Module.symvers" ] || { echo "run tools/build_kernel.sh first"; exit 1; }
KVER=$(cat "$KDIR/include/config/kernel.release")
EXTRA="$STAGE/lib/modules/$KVER/extra"
mkdir -p "$WORK" "$EXTRA"

# apply a quilt-style series ($1=dir with sources, $2=patch/<comp> dir)
apply_series() {
  local d=$1 pdir=$2
  [ -f "$d/.bsp-patched" ] && return
  grep -v '^\s*#' "$pdir/series" | grep -v '^\s*$' | while read -r pname; do
    echo "[PATCH $(basename "$pdir")] $pname"
    patch -d "$d" -p1 -N -s --no-backup-if-mismatch < "$pdir/$pname"
  done
  touch "$d/.bsp-patched"
}

# --- mali_kbase ---
if [ ! -d "$WORK/mali_km" ]; then
  tar -xf "$DLDIR/mali-g31_km_v1.3.0.tar.gz" -C "$WORK"
fi
apply_series "$WORK/mali_km" "$PATCHROOT/mali-km"
MALI_SRC="$WORK/mali_km/drivers/gpu/arm/midgard"
echo "[BUILD] mali_kbase"
make -C "$MALI_SRC" -j"$J" \
  KDIR="$KDIR" ARCH=arm64 BUILD=release CROSS_COMPILE="$CROSS_COMPILE" \
  MALI_PLATFORM_NAME=devicetree CONFIG_MALI_MIDGARD=m
cp "$MALI_SRC/mali_kbase.ko" "$EXTRA/"

# --- uvcs_drv ---
if [ ! -d "$WORK/uvcs" ]; then
  mkdir -p "$WORK/uvcs"
  tar -xf "$DLDIR/uvcs_kernel_package_v4.3.3.0.tar.bz2" -C "$WORK/uvcs"
fi
UVCS_S="$WORK/uvcs/uvcs_kernel_package"
echo "[BUILD] uvcs_drv"
# NB: the uvcs makefile uses $(PWD), so a real cd is required (make -C alone
# leaves PWD pointing elsewhere and kbuild descends into the wrong dir)
( cd "$UVCS_S/src/makefile"
  export UVCS_SRC="$UVCS_S/src" UVCS_INC="$UVCS_S" VCP4_SRC="$UVCS_S/src"
  make KERNELDIR="$KDIR" CROSS_COMPILE="$CROSS_COMPILE" ip_option=0x3000A )
cp "$UVCS_S/src/makefile/uvcs_drv.ko" "$EXTRA/"

# --- mmngr / mmngrbuf / vspm / vspm_if (renesas-rcar repos + recipe patches) ---
# Invocation contract from rz-modules-common.inc + each drv/Makefile:
#   env CP=cp KERNELSRC=<kernel build> INCSHARED=<shared include dir>, real cd
#   (Makefiles use $(PWD)); mmngr's headers/symvers land in $KERNELSRC/include
#   and vspmif links against $KERNELSRC/include/vspm.symvers.
export CP=cp KERNELSRC="$KDIR" INCSHARED="$KDIR/include" LDFLAGS=

# mmngr_drv now comes from the roseapple fork with patch/mmngr{,buf} already
# baked in as commits (see mmngr.mk) — nothing to apply here.
echo "[BUILD] mmngr"
( cd "$BSPDIR/src/mmngr_drv/mmngr_drv/mmngr/mmngr-module/files/mmngr/drv"
  export MMNGR_CONFIG=MMNGR_RZV2H MMNGR_SSP_CONFIG=MMNGR_SSP_DISABLE MMNGR_IPMMU_MMU_CONFIG=IPMMU_MMU_DISABLE
  make all
  cp mmngr.ko "$EXTRA/"; cp Module.symvers "$KDIR/include/mmngr.symvers" )

echo "[BUILD] mmngrbuf"
( cd "$BSPDIR/src/mmngr_drv/mmngr_drv/mmngrbuf/mmngrbuf-module/files/mmngrbuf/drv"
  make all
  cp mmngrbuf.ko "$EXTRA/"; cp Module.symvers "$KDIR/include/mmngrbuf.symvers" )

# vspm_drv now from the roseapple fork with patch/vspm baked in (see vspm.mk)
echo "[BUILD] vspm"
( cd "$BSPDIR/src/vspm_drv/vspm-module/files/vspm/drv"
  make all
  cp vspm.ko "$EXTRA/"; cp Module.symvers "$KDIR/include/vspm.symvers"
  # recipe's do_install shares these for vspmif's build
  cp ../include/*.h "$KDIR/include/" )

# vspmif_drv now from the roseapple fork with patch/vspmif-drv baked in (vspm.mk)
echo "[BUILD] vspm_if"
( cd "$BSPDIR/src/vspmif_drv/vspm_if-module/files/vspm_if/drv"
  make all
  cp vspm_if.ko "$EXTRA/" )

depmod -b "$STAGE" "$KVER" 2>/dev/null || true
echo "[INFO] staged modules:"
ls -la "$EXTRA"
