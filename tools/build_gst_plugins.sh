#!/bin/bash
set -euo pipefail

# mmdebstrap customize-hook (also runnable standalone as root):
# builds the Renesas multimedia userspace INSIDE the target rootfs against
# Ubuntu 26.04's real GStreamer 1.26, following each Yocto recipe's method:
#   1. stage shared kernel-module headers into /usr/local/include
#      (the convention rz-modules-common.inc uses via RENESAS_DATADIR)
#   2. mmngr + mmngrbuf user libs      — autotools (mmngr_lib.inc)
#   3. vspmif user lib (libvspm)       — plain make in if/, VSPM_LEGACY_IF=1
#   4. gst-omx                         — meson, target=rz, Renesas gstomx.conf
#   5. vspmfilter                      — autotools + VTOP ioctl patch

BSPDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ROOTDIR=${1:?usage: build_gst_plugins.sh <rootfs-dir>}
SRC="$BSPDIR/src"
B="$ROOTDIR/opt/bsp-build"

[ -d "$SRC/gst-omx" ] || { echo "run 'make fetch' first"; exit 1; }
mkdir -p "$B"
for d in gst-omx vspmfilter mmngr_lib vspmif_lib; do
  rm -rf "$B/$d"; cp -a "$SRC/$d" "$B/"
done
# No build-time gst patches: vspmfilter and vspmif_lib both come from roseapple
# forks with their AI SDK patch series baked in (gstreamer.mk / vspm.mk).

# --- shared kernel-module headers → /usr/local/include (Yocto staging analog) ---
INC="$ROOTDIR/usr/local/include"
mkdir -p "$INC"
cp "$SRC/mmngr_drv/mmngr_drv/mmngr/mmngr-module/files/mmngr/include/"*.h        "$INC/"
cp "$SRC/mmngr_drv/mmngr_drv/mmngrbuf/mmngrbuf-module/files/mmngrbuf/include/"*.h "$INC/"
cp "$SRC/vspm_drv/vspm-module/files/vspm/include/"*.h                            "$INC/"
cp "$SRC/vspmif_drv/vspm_if-module/files/vspm_if/include/"*.h                    "$INC/"  # vspm_if.h
cp "$B/vspmif_lib/vspm_if-module/files/vspm_if/include/"*.h                      "$INC/"  # vspm_public.h (ISU-patched), fdpm_api.h
# OMX headers from the codec blob package (postcfg already put them in /usr/include/omxr)
cp "$ROOTDIR/usr/include/omxr/"*.h "$INC/"

# gstomx.conf from the recipe, core-name pointed at the blob's real location;
# meson's config/rz/meson.build also expects it inside the source tree
mkdir -p "$ROOTDIR/etc/xdg" "$B/gst-omx/config/rz"
sed 's,@RENESAS_DATADIR@/lib,/usr/lib/aarch64-linux-gnu,g' \
  "$BSPDIR/vendor/gstomx.conf" > "$ROOTDIR/etc/xdg/gstomx.conf"
cp "$ROOTDIR/etc/xdg/gstomx.conf" "$B/gst-omx/config/rz/gstomx.conf"

# inside an mmdebstrap hook resolv.conf is already managed; standalone runs need it
[ -s "$ROOTDIR/etc/resolv.conf" ] || cp /etc/resolv.conf "$ROOTDIR/etc/resolv.conf" || true

# /dev may be absent (tar-in reruns strip it — userns can't mknod); bind-mount
# the host nodes for the duration of the build. Guarded: no-op when mmdebstrap
# already provides them (normal `make rootfs` hook path).
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
  build-essential autoconf automake libtool pkg-config meson ninja-build \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev

export CPPFLAGS="-I/usr/local/include"
export CFLAGS="-O2 -I/usr/local/include"
export LDFLAGS="-L/usr/lib/aarch64-linux-gnu"
export INCSHARED=/usr/local/include   # raw Renesas Makefiles use -I$(INCSHARED)
LIBDIR=/usr/lib/aarch64-linux-gnu

# --- mmngr / mmngrbuf user libs (autotools, per mmngr_lib.inc) ---
for d in mmngr mmngrbuf; do
  cd /opt/bsp-build/mmngr_lib/libmmngr/$d
  autoreconf -fi
  ./configure --prefix=/usr --libdir=$LIBDIR --includedir=/usr/local/include
  make -j"$(nproc)"
  make install
done
ldconfig

# --- vspmif user lib: libvspm.so (plain make, per vspmif-user-module.bb) ---
export VSPM_LEGACY_IF=1
cd /opt/bsp-build/vspmif_lib/vspm_if-module/files/vspm_if/if
rm -f libvspm.so*
make -j"$(nproc)"
install -m 755 libvspm.so* $LIBDIR/
install -m 644 ../include/vspm_public.h ../include/fdpm_api.h /usr/local/include/ 2>/dev/null || true
ldconfig

# --- gst-omx (meson, target=rz, per gstreamer1.0-omx_1.22.12.bbappend) ---
cd /opt/bsp-build/gst-omx
meson setup build --prefix=/usr --libdir=$LIBDIR \
  -Dtarget=rz -Dheader_path=/usr/local/include -Dexamples=disabled
ninja -C build
ninja -C build install

# --- vspmfilter (autotools) ---
cd /opt/bsp-build/vspmfilter
autoreconf -fi
./configure --prefix=/usr --libdir=$LIBDIR
make -j"$(nproc)"
make install

ldconfig
echo "== plugin sanity =="
gst-inspect-1.0 omx 2>&1 | head -5 || echo "[WARN] omx plugin not registering"
gst-inspect-1.0 vspmfilter 2>&1 | head -3 || echo "[WARN] vspmfilter not registering"

# drop the build toolchain we installed above (~350MB) — runtime keeps only
# the built libs/plugins
apt-get purge -y build-essential autoconf automake libtool pkg-config \
  meson ninja-build libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
apt-get autoremove -y --purge
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

rm -rf "$B"
rm -f "$ROOTDIR/etc/bsp-gst-failed"
echo "[INFO] gst plugins built & installed inside rootfs"
