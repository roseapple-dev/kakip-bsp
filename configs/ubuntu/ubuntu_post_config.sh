#!/bin/bash
set -euo pipefail

# Post-config for the GNOME rootfs: install kernel modules + vendor blobs
# from the AI SDK v6.00 package, then wire GNOME/mutter to the GLES-only
# Mali blob using the same tricks as NXP flexbuild's i.MX95 desktop
# (remove Mesa's EGL/GLES/gbm, patchelf mutter GL→GLES at boot).
# Run with sudo after configs/ubuntu/ubuntu_desktop_arm64.sh.

BSPDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ROOTDIR=${1:?usage: sudo ubuntu_post_config.sh <rootfs-dir>}
DLDIR="$BSPDIR/dl"
STAGE="$BSPDIR/build/modules-stage"
# scratch under /tmp: as an mmdebstrap hook we run as a subuid user that can
# read the BSP tree (traverse ACL on ~) but must not need to write into it
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
LIBDIR="$ROOTDIR/usr/lib/aarch64-linux-gnu"

[ -d "$ROOTDIR" ] || { echo "rootfs not found: $ROOTDIR"; exit 1; }
[ -d "$STAGE/lib/modules" ] || { echo "run build_kernel.sh + build_modules.sh first"; exit 1; }

# --- kernel modules (in-tree + extra) ---
cp -a "$STAGE/lib/modules" "$ROOTDIR/lib/"

# --- GPU: Mali UM blob (wayland variant, GLES+CL) ---
# The blob's top-level wrapper libs are real ELFs with NO SONAME that dlopen
# libmali.so at runtime — install them AS the soname filenames. Mesa/glvnd
# runtime files are moved aside with dpkg-divert: plain rename does NOT work,
# ldconfig re-links the sonames back to them (SONAME unchanged; bit us on
# first Kakip bring-up, see MANIFEST).
tar -xf "$DLDIR/mali-g31_um_v1.3.0.tar.gz" -C "$WORK"
MALI_UM="$WORK/mali_um/usr/lib"
install -D -m 755 "$MALI_UM/CL_GLES/mali_wayland/libmali.so" "$LIBDIR/libmali.so"
install -m 755 "$MALI_UM/libEGL.so"         "$LIBDIR/libEGL.so.1"
install -m 755 "$MALI_UM/libGLESv2.so"      "$LIBDIR/libGLESv2.so.2"
install -m 755 "$MALI_UM/libGLESv1_CM.so"   "$LIBDIR/libGLESv1_CM.so.1"
install -m 755 "$MALI_UM/libgbm.so"         "$LIBDIR/libgbm.so.1"
install -m 755 "$MALI_UM/libwayland-egl.so" "$LIBDIR/libwayland-egl.so.1"
install -m 755 "$MALI_UM/libOpenCL.so"      "$LIBDIR/libOpenCL.so.1"

# divert the Mesa/glvnd files those sonames used to resolve to (apt- and
# ldconfig-proof); exact versioned names discovered inside the chroot
chroot "$ROOTDIR" /bin/bash -e <<'DIVEOF'
mkdir -p /usr/lib/mali-diverted
cd /usr/lib/aarch64-linux-gnu
for pat in "libEGL.so.1.*" "libGLESv2.so.2.*" "libGLESv1_CM.so.1.*" "libgbm.so.1.*" "libwayland-egl.so.1.*"; do
  for f in $pat; do
    case "$f" in (*"*"*) continue;; esac   # unmatched glob
    dpkg-divert --local --divert "/usr/lib/mali-diverted/$f" --rename "/usr/lib/aarch64-linux-gnu/$f"
  done
done
DIVEOF

# --- VPU codec userspace (v4.3.3.0) + omxr configs ---
tar -xf "$DLDIR/codec_pkg_product_v4.3.3.0.tar.gz" -C "$WORK"
CODEC="$WORK/codec_pkg_product_v4.3.3.0"
find "$CODEC" -name "*.so.*" -path "*/lib/*" -exec install -D -m 644 -t "$LIBDIR" {} \;
mkdir -p "$ROOTDIR/etc/omxr"
find "$CODEC" -name "omxr_config_*.txt" -exec install -D -m 644 -t "$ROOTDIR/etc/omxr" {} \;
# OMX headers — needed later by tools/build_gst_plugins.sh (gst-omx target=rz)
mkdir -p "$ROOTDIR/usr/include/omxr"
find "$CODEC" -path "*/include/*" -name "*.h" -exec install -D -m 644 -t "$ROOTDIR/usr/include/omxr" {} \;
# soname symlinks (libomxr_*.so.3.0.0 -> .so.3 -> .so, uvcs likewise)
for so in "$LIBDIR"/libomxr_*.so.*.*.* "$LIBDIR"/libuvcs_*.so.*.*.*; do
  [ -e "$so" ] || continue
  base=$(basename "$so"); stem=${base%%.so.*}; ver=${base#*.so.}; major=${ver%%.*}
  ln -sf "$base" "$(dirname "$so")/$stem.so.$major"
  ln -sf "$stem.so.$major" "$(dirname "$so")/$stem.so"
done

# DRP / DRP-AI / OpenCVA removed for now (kernel DRP stack not enabled).
# To restore: re-add the libdrp_api.so / Codec_Bin.bin / OpenCV_Bin.bin /
# lib_tvm / drpai.h installs — the blobs are still cached in dl/.

# --- mmngr/vspm userspace libs are built by tools/build_gst_plugins.sh (in-chroot) ---

# --- GNOME/mutter × Mali integration ---
install -D -m 755 "$BSPDIR/system/gpuconfig"          "$ROOTDIR/etc/gpuconfig"
install -D -m 644 "$BSPDIR/system/gpuconfig.service"  "$ROOTDIR/lib/systemd/system/gpuconfig.service"
install -D -m 755 "$BSPDIR/system/gnome/gen-monitors.py"      "$ROOTDIR/usr/local/bin/gen-monitors.py"
install -D -m 644 "$BSPDIR/system/gnome/gen-monitors.service" "$ROOTDIR/lib/systemd/system/gen-monitors.service"
install -D -m 644 "$BSPDIR/system/udev/99-rzv2h-accel.rules"  "$ROOTDIR/etc/udev/rules.d/99-rzv2h-accel.rules"
install -D -m 644 "$BSPDIR/system/vkms.service"              "$ROOTDIR/lib/systemd/system/vkms.service"
install -D -m 755 "$BSPDIR/tools/resizerfs" "$ROOTDIR/usr/bin/resizerfs"
install -D -m 644 "$BSPDIR/system/resizerfs.service" "$ROOTDIR/lib/systemd/system/resizerfs.service"

cat > "$ROOTDIR/etc/environment" <<'EOT'
COGL_DRIVER=gles2
CLUTTER_DRIVER=gles2
GDK_GL=gles
QT_QPA_PLATFORM=wayland
EOT

# Mali blob is Wayland-only: force GDM to Wayland session, no X fallback
mkdir -p "$ROOTDIR/etc/gdm3"
if [ -f "$ROOTDIR/etc/gdm3/custom.conf" ]; then
  sed -i 's/^#*WaylandEnable=.*/WaylandEnable=true/' "$ROOTDIR/etc/gdm3/custom.conf"
else
  printf "[daemon]\nWaylandEnable=true\n" > "$ROOTDIR/etc/gdm3/custom.conf"
fi

if ! grep -q '^AutomaticLoginEnable' "$ROOTDIR/etc/gdm3/custom.conf"; then
  sed -i '/^\[daemon\]/a AutomaticLoginEnable=true\nAutomaticLogin=ubuntu' "$ROOTDIR/etc/gdm3/custom.conf"
fi

# --- clock / apt (RZ/V2H RTC probe fails with -ETIMEDOUT, so the boot clock is
# wrong until NTP syncs; without this apt rejects the mirror Release as "not
# valid yet"). Skip apt's date check; chrony/clock-epoch (below) fix the clock. ---
mkdir -p "$ROOTDIR/etc/apt/apt.conf.d"
cat > "$ROOTDIR/etc/apt/apt.conf.d/99no-check-date" <<'ACONF'
Acquire::Check-Date "false";
Acquire::Check-Valid-Until "false";
ACONF

chroot "$ROOTDIR" /bin/bash -e <<'RDEOF'
mkdir -p /etc/systemd/system/sysinit.target.wants
ln -sf /lib/systemd/system/vkms.service /etc/systemd/system/sysinit.target.wants/vkms.service

if [ -f /usr/lib/udev/rules.d/61-mutter.rules ]; then
  grep -v vkms /usr/lib/udev/rules.d/61-mutter.rules > /etc/udev/rules.d/61-mutter.rules
fi

# Never suspend an always-on board: mask every path into system sleep.
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# GNOME power/idle + remote-desktop defaults via dconf, for user sessions and
# the GDM greeter. The greeter needs its own profile carrying system-db:gdm --
# Ubuntu 26.04's stock /usr/share/dconf/profile/gdm omits it, so a gdm.d db on
# its own is a no-op.
mkdir -p /etc/dconf/db/local.d /etc/dconf/db/gdm.d /etc/dconf/profile
printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
printf 'user-db:user\nsystem-db:gdm\nfile-db:/var/lib/gdm3/greeter-dconf-defaults\n' > /etc/dconf/profile/gdm
cat > /etc/dconf/db/local.d/00-kakip-desktop <<'CONF'
[org/gnome/settings-daemon/plugins/power]
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'

[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/desktop/remote-desktop/rdp]
enable=true
view-only=false
tls-cert='/home/ubuntu/.local/share/gnome-remote-desktop/tls.crt'
tls-key='/home/ubuntu/.local/share/gnome-remote-desktop/tls.key'
CONF
cp /etc/dconf/db/local.d/00-kakip-desktop /etc/dconf/db/gdm.d/00-kakip-desktop
dconf update || true

# Enable the user-mode RDP server for every session.
mkdir -p /etc/systemd/user/gnome-session.target.wants
ln -sf /usr/lib/systemd/user/gnome-remote-desktop.service \
       /etc/systemd/user/gnome-session.target.wants/gnome-remote-desktop.service

SKEL_GRD=/etc/skel/.local/share/gnome-remote-desktop
SKEL_KR=/etc/skel/.local/share/keyrings
mkdir -p "$SKEL_GRD" "$SKEL_KR"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj /CN=kakip \
  -keyout "$SKEL_GRD/tls.key" -out "$SKEL_GRD/tls.crt" >/dev/null 2>&1
chmod 600 "$SKEL_GRD/tls.key"
cat > "$SKEL_KR/login.keyring" <<'KEYRING'
[keyring]
display-name=Login
ctime=0
mtime=0
lock-on-idle=false
lock-after=false

[1]
item-type=0
display-name=GNOME Remote Desktop RDP credentials
secret={'username': <'ubuntu'>, 'password': <'ubuntu'>}
mtime=0
ctime=0

[1:attribute0]
name=xdg:schema
type=string
value=org.gnome.RemoteDesktop.RdpCredentials
KEYRING
chmod 600 "$SKEL_KR/login.keyring"
RDEOF

chroot "$ROOTDIR" /bin/bash -e <<'EOF'
ldconfig
id -u ubuntu &>/dev/null || useradd -m -d /home/ubuntu -s /bin/bash ubuntu
echo "ubuntu:ubuntu" | chpasswd
usermod -aG sudo,video,render,dialout ubuntu || true
usermod -aG render,video gdm 2>/dev/null || true  # greeter needs /dev/mali0 + KMS
usermod -aG render,video gdm 2>/dev/null || true
ln -sf /lib/systemd/system/gpuconfig.service /etc/systemd/system/graphical.target.wants/gpuconfig.service
ln -sf /lib/systemd/system/resizerfs.service /etc/systemd/system/multi-user.target.wants/resizerfs.service
ln -sf /lib/systemd/system/gen-monitors.service /etc/systemd/system/graphical.target.wants/gen-monitors.service
systemctl set-default graphical.target
# broken RTC (rtc-rtca3 -ETIMEDOUT): chrony (pulled by ubuntu-desktop-minimal,
# replaced timesyncd since 25.10) syncs over NTP once online; before/without
# NTP, systemd PID1 bumps the boot clock forward to /usr/lib/clock-epoch's
# mtime (= build time), never back to the deep past.
touch /usr/lib/clock-epoch
depmod -a "$(ls /lib/modules | head -1)" || true
sed -i -e "s/.*en_US.UTF-8.*/en_US.UTF-8 UTF-8/" /etc/locale.gen
locale-gen >/dev/null 2>&1 || true
update-locale LANG=en_US.UTF-8 || true
printf "Build: $(date --rfc-3339 seconds)\n" >> /etc/buildinfo
EOF

echo "[INFO] post-config done — run tools/build_gst_plugins.sh to add gst-omx/vspmfilter/mmngr libs"
