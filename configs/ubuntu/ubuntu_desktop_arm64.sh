#!/bin/bash
set -euo pipefail

# Kakip — Ubuntu 26.04 (resolute) GNOME desktop rootfs, fully ROOTLESS:
# mmdebstrap --mode=unshare bootstraps the desktop, then runs
# ubuntu_post_config.sh (blobs + GNOME/mutter wiring) and optionally
# build_gst_plugins.sh as customize-hooks — inside the namespace we are root,
# so chroot/install work without sudo. Output is a tarball (ownership is
# recorded correctly inside it); tools/create_image.sh turns it into ext4
# via fakeroot.
#
# Usage: ubuntu_desktop_arm64.sh <output-rootfs.tar> [--skip-gst]

BSPDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OUT_TAR=${1:?usage: ubuntu_desktop_arm64.sh <output-rootfs.tar> [--skip-gst]}
SKIP_GST=${2:-}

SUITE=resolute
ARCH=arm64
KEYRING="/usr/share/keyrings/ubuntu-archive-keyring.gpg"
MIRRORS=(http://ports.ubuntu.com/ubuntu-ports)

BASE_PACKAGES=(
  init udev sudo vim apt file zstd parted fdisk dosfstools iputils-ping
  wget curl ca-certificates systemd systemd-sysv psmisc ethtool iproute2 openssh-server
  openssh-client patchelf htop util-linux lshw keyutils wpasupplicant
  tcpdump mtd-utils pciutils usbutils lsb-release iptables
  dmidecode flex fbset
  mmc-utils i2c-tools lm-sensors net-tools locales
  can-utils v4l-utils alsa-utils
)
DESKTOP_PACKAGES=(
  ubuntu-desktop-minimal gdm3 network-manager
  fonts-dejavu-core fonts-noto-cjk fonts-noto-color-emoji fontconfig
  gstreamer1.0-tools gstreamer1.0-plugins-good gstreamer1.0-plugins-bad
  gstreamer1.0-libav libgstreamer1.0-0 libgstreamer-plugins-base1.0-0
)
PACKAGES=("${BASE_PACKAGES[@]}" "${DESKTOP_PACKAGES[@]}")

HOOKS=(--customize-hook="bash '$BSPDIR/configs/ubuntu/ubuntu_post_config.sh' \"\$1\"")
if [ "$SKIP_GST" != "--skip-gst" ]; then
  # non-fatal: a gst build failure marks the rootfs instead of throwing away
  # the whole (long) bootstrap — check for /etc/bsp-gst-failed afterwards
  HOOKS+=(--customize-hook="bash '$BSPDIR/tools/build_gst_plugins.sh' \"\$1\" || { echo '[WARN] gst hook failed'; touch \"\$1/etc/bsp-gst-failed\"; }")
fi

mmdebstrap \
  --arch=$ARCH \
  --mode=auto \
  --variant=standard \
  --components=main,restricted,universe \
  --keyring="$KEYRING" \
  --aptopt='Acquire::Retries=5' \
  --aptopt='APT::Get::Assume-Yes=true' \
  --aptopt='DPkg::Options::=--force-confnew' \
  --aptopt='Acquire::Languages="none"' \
  --aptopt='APT::Install-Recommends "false"' \
  --skip=download/bytecode \
  --include="$(IFS=,; echo "${PACKAGES[*]}")" \
  "${HOOKS[@]}" \
  "$SUITE" \
  "$OUT_TAR" \
  "${MIRRORS[@]}"

echo "[INFO] rootfs tarball: $OUT_TAR"
