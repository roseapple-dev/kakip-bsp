#!/bin/bash
set -euo pipefail

# Assemble the flashable .img — ROOTLESS:
# rootfs comes in as a tarball (from mmdebstrap --mode=unshare); fakeroot
# preserves ownership across extract → mke2fs -d (mke2fs 1.47.0 has no tar
# input support, so the fakeroot state-file trick does the job).
# p1 FAT32 boot (Image + DTB, via mtools), p2 ext4 rootfs.

BSPDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ROOTFS_TAR=${1:?usage: create_image.sh <rootfs.tar> <output.img>}
OUT_IMG=${2:?usage: create_image.sh <rootfs.tar> <output.img>}
BUILD=$(dirname "$OUT_IMG")
mkdir -p "$BUILD"

KERNEL_IMAGE=${KERNEL_IMAGE:-"$BSPDIR/build/kernel/arch/arm64/boot/Image"}
DTB=${DTB:-"$BSPDIR/build/kernel/arch/arm64/boot/dts/renesas/r9a09g057h48-kakip.dtb"}
[ -f "$KERNEL_IMAGE" ] && [ -f "$DTB" ] || { echo "[ERROR] run 'make kernel' first (or set KERNEL_IMAGE=/DTB=)"; exit 1; }
[ -f "$ROOTFS_TAR" ] || { echo "[ERROR] rootfs tar not found: $ROOTFS_TAR"; exit 1; }

BOOT_SIZE_MIB=200
BOOT_IMG="$BUILD/boot.img"
ROOT_IMG="$BUILD/root.img"

# FAT layout matches the Kakip U-Boot env (sd0load):
#   fatload mmc 0:1 ... boot/{Image,<dtb>}
# (DRP firmware bins dropped along with the DRP kernel patches — restore
#  OpenCV_Bin.bin/Codec_Bin.bin here when the DRP stack is ported to 6.1)
echo "[INFO] boot partition (FAT16): boot/Image + boot/$(basename "$DTB")"
rm -f "$BOOT_IMG"
# FAT16, matching the official Kakip/RDK images — U-Boot 2021.10's fatload
# chokes on the FAT32/512B-cluster layout mkfs picks with -F32 (verified)
mkfs.fat -F16 -n boot -C "$BOOT_IMG" $((BOOT_SIZE_MIB * 1024)) >/dev/null
mmd -i "$BOOT_IMG" ::boot
mcopy -i "$BOOT_IMG" "$KERNEL_IMAGE" ::boot/Image
mcopy -i "$BOOT_IMG" "$DTB" "::boot/$(basename "$DTB")"
mcopy -i "$BOOT_IMG" "$BSPDIR/dl/Codec_Bin.bin" ::boot/Codec_Bin.bin
mcopy -i "$BOOT_IMG" "$BSPDIR/dl/OpenCV_Bin.bin" ::boot/OpenCV_Bin.bin

echo "[INFO] rootfs partition (ext4) from $(basename "$ROOTFS_TAR") via fakeroot"
STAGING="$BUILD/rootfs-staging"
FAKESTATE="$BUILD/.fakeroot-state"
rm -rf "$STAGING" "$FAKESTATE" "$ROOT_IMG"
mkdir -p "$STAGING"
TAR_MIB=$(( $(stat -c %s "$ROOTFS_TAR") / 1024 / 1024 ))
ROOTFS_SIZE_MIB=$(( TAR_MIB + TAR_MIB / 20 + 256 ))   # tar + 5% fs overhead + small slack; resizerfs fills the SD on first boot
fakeroot -s "$FAKESTATE" tar -xpf "$ROOTFS_TAR" -C "$STAGING"
fakeroot -i "$FAKESTATE" mke2fs -q -t ext4 -L rootfs -d "$STAGING" "$ROOT_IMG" "${ROOTFS_SIZE_MIB}M"
rm -rf "$STAGING" "$FAKESTATE"

BOOT_START=8192
BOOT_SECTORS=$(( BOOT_SIZE_MIB * 1024 * 1024 / 512 ))
ROOT_START=$(( BOOT_START + BOOT_SECTORS ))
ROOT_SECTORS=$(( ROOTFS_SIZE_MIB * 1024 * 1024 / 512 ))
TOTAL_SECTORS=$(( ROOT_START + ROOT_SECTORS ))

echo "[INFO] assembling $OUT_IMG ($(( TOTAL_SECTORS / 2048 ))MiB)"
rm -f "$OUT_IMG"
truncate -s $(( TOTAL_SECTORS * 512 )) "$OUT_IMG"
sfdisk -q "$OUT_IMG" <<EOF
label: dos
unit: sectors

${BOOT_START},${BOOT_SECTORS},c,*
${ROOT_START},${ROOT_SECTORS},83
EOF

dd if="$BOOT_IMG" of="$OUT_IMG" bs=512 seek=$BOOT_START conv=notrunc status=none
dd if="$ROOT_IMG" of="$OUT_IMG" bs=512 seek=$ROOT_START conv=notrunc status=none
rm -f "$BOOT_IMG" "$ROOT_IMG"

# Kakip boots from SD (eSD boot). BootROM layout (verified against the RDK
# official image + kakip firmware-pack.bb):
#   sector 1   boot-parameter block (bootparameter tool output; without this
#              BootROM drops to "SCI Download mode (parameter error)")
#   sector 8   BL2 (TF-A 2.10 w/ Kakip LPDDR4 config, BOARD=kakip_1)
#   sector 768 FIP (BL31 + U-Boot)
# All live before p1@8192.
KAKIP_BP="$BSPDIR/dl/bootloader/kakip/bp-kakip.bin"
KAKIP_BL2="$BSPDIR/dl/bootloader/kakip/bl2-kakip.bin"
KAKIP_FIP="$BSPDIR/dl/bootloader/kakip/fip-kakip.bin"
if [ -f "$KAKIP_BP" ] && [ -f "$KAKIP_BL2" ] && [ -f "$KAKIP_FIP" ]; then
  echo "[INFO] embedding Kakip boot-param (sector 1) + BL2 (sector 8) + FIP (sector 768)"
  dd if="$KAKIP_BP"  of="$OUT_IMG" bs=512 seek=1   conv=notrunc status=none
  dd if="$KAKIP_BL2" of="$OUT_IMG" bs=512 seek=8   conv=notrunc status=none
  dd if="$KAKIP_FIP" of="$OUT_IMG" bs=512 seek=768 conv=notrunc status=none
else
  echo "[WARN] dl/bootloader/kakip/ incomplete — image has no SD bootloader (Kakip won't boot)"
fi

echo "[INFO] done: $OUT_IMG"
