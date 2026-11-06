#!/bin/bash
set -euo pipefail

# mmdebstrap customize-hook (also runnable standalone as root): builds
# libcamera INSIDE the target rootfs and installs it to /usr.

BSPDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ROOTDIR=${1:?usage: build_libcamera.sh <rootfs-dir>}
SRC="$BSPDIR/src"
B="$ROOTDIR/opt/bsp-build"

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

[ -d "$SRC/libcamera" ] || { echo "run 'make fetch' first"; exit 1; }
rm -rf "$B/libcamera"; mkdir -p "$B/libcamera"
cp -a "$SRC/libcamera/." "$B/libcamera/"
rm -rf "$B/libcamera/.git"
if [ -s "$BSPDIR/patch/libcamera/series" ]; then
  apply_series "$B/libcamera" "$BSPDIR/patch/libcamera"
fi

[ -s "$ROOTDIR/etc/resolv.conf" ] || cp /etc/resolv.conf "$ROOTDIR/etc/resolv.conf" || true

# /dev may be absent (tar-in reruns strip it — userns can't mknod); bind-mount
# the host nodes for the duration of the build.
CLEANUP=()
cleanup() {
  for m in "${CLEANUP[@]}"; do umount "$m" 2>/dev/null || true; done
}
trap cleanup EXIT
mkdir -p "$ROOTDIR/dev" "$ROOTDIR/proc"
for f in null zero urandom random tty; do
  if [ ! -e "$ROOTDIR/dev/$f" ]; then
    touch "$ROOTDIR/dev/$f"
    mount --bind "/dev/$f" "$ROOTDIR/dev/$f" && CLEANUP+=("$ROOTDIR/dev/$f")
  fi
done
if ! mountpoint -q "$ROOTDIR/proc"; then
  mount -t proc proc "$ROOTDIR/proc" && CLEANUP+=("$ROOTDIR/proc")
fi

chroot "$ROOTDIR" /bin/bash -e <<'EOF'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  meson ninja-build pkg-config g++ \
  libyaml-dev python3-yaml python3-ply python3-jinja2 libgnutls28-dev openssl \
  libudev-dev libevent-dev libdrm-dev libtiff-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev

cd /opt/bsp-build/libcamera
meson setup build --prefix=/usr --buildtype=release \
  -Dpipelines=simple -Dipas=softisp -Dcam=enabled -Dgstreamer=enabled \
  -Dqcam=disabled -Dlc-compliance=disabled -Ddocumentation=disabled \
  -Dpycamera=disabled -Dtest=false -Dtracing=disabled -Dv4l2=false \
  -Dsoftisp-gpu=disabled
ninja -C build
ninja -C build install
ldconfig

# runtime libs came in as dependencies of the -dev packages; mark them manual
# so the autoremove below keeps them.
for f in /usr/bin/cam $(find /usr/lib -path '*libcamera*' -name '*.so*' -type f); do
  ldd "$f" 2>/dev/null | awk '/=> \//{print $3}'
done | sort -u | while read -r lib; do
  dpkg -S "$lib" 2>/dev/null | grep -v '^diversion by' | sed 's#: /.*##' | tr ',' '\n'
done | tr -d ' ' | sed 's/:.*//' | sort -u | xargs -r apt-mark manual

echo "== libcamera sanity =="
cam -l || echo "[WARN] cam does not run"
gst-inspect-1.0 libcamerasrc 2>&1 | head -3 || echo "[WARN] libcamerasrc not registering"

# python3-yaml and openssl are part of the desktop image: keep them
apt-get purge -y meson ninja-build pkg-config g++ \
  libyaml-dev python3-ply python3-jinja2 libgnutls28-dev \
  libudev-dev libevent-dev libdrm-dev libtiff-dev \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
apt-get autoremove -y --purge
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

rm -rf "$B"
rm -f "$ROOTDIR/etc/bsp-libcamera-failed"
echo "[INFO] libcamera built & installed inside rootfs"
