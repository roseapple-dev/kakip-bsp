# Provenance manifest — RZ/V2H Ubuntu 26.04 GNOME BSP

Source of truth: **Renesas AI SDK v6.00 (RTK0EF0180F06000SJ)**, fully local at
`../yocto/`. Every pin below was read out of the actual Yocto recipes in
`rzv2h_ai-sdk_yocto_recipe_v6.00` — nothing is guessed, and nothing needs the
network (all git tarballs are in `oss_pkg_rzv_v6.00/downloads`).

## Exact pins (from the recipes)

| Component | Version / SRCREV | Recipe |
|---|---|---|
| kernel | 6.1.141-cip43, branch `rz-6.1-cip43`, `10b3443b44fe…` | `meta-rz-bsp/recipes-kernel/linux/linux-renesas_6.1.bb` |
| kernel config | in-tree arm64 `defconfig` (KBUILD_DEFCONFIG, alldefconfig) | same |
| kernel patches | codec×2 + drpai×4 + mali×1 (DRP-AI bbappend supersedes codec's 0003 clk patch) | `meta-rz-features/*/recipes-kernel/…` |
| Mali G31 UM/KM | v1.3.0 (UM blob wayland/fbdev; KM source + 5 patches) | `meta-rz-graphics/recipes-graphics/mali/…` |
| VPU codec | v4.3.3.0 (`libomxr_*`/`libuvcs_*` blobs; uvcs KM source, `ip_option=0x3000A`) | `meta-rz-codecs/…` |
| gst-omx | branch `RZ/1.22.12`, SRCREV `189acf4d…` | `gstreamer1.0-omx_1.22.12.bbappend` |
| vspmfilter | branch `rz_g2l`, SRCREV `e4e24c82…`, +VTOP ioctl patch | `gstreamer1.0-plugin-vspmfilter.bb` |
| TVM runtime | `libtvm_runtime.so.2.5.1` (blob) | `meta-rz-drpai/recipes-core/lib-tvm` |
| DRP fw / OpenCVA | `Codec_Bin.bin`, `OpenCV_Bin.bin`, `libdrp_api.so` (blobs) | `recipes-drp`, `recipes-oca` |
| u-boot | 2024.07, SRCREV `8e0b7870…`, `rzv2h-evk-ver1_defconfig` | `recipes-bsp/u-boot_2024.07.bb` |
| TF-A | 2.10, SRCREV `3c83dd6f…`, PLAT=v2h BOARD=evk_1 | `recipes-bsp/trusted-firmware-a_2.10.bb` |

Closed blobs (no source anywhere, reused as-is): Mali UM, codec `libomxr_*`/
`libuvcs_*`, `libdrp_api.so`, `libtvm_runtime.so`, `Codec_Bin.bin`,
`OpenCV_Bin.bin`. License: `codec_pkg_product_v4.3.3.0/License.txt` +
`references/linux_licenses.zip` — check redistribution terms before shipping.

## What this BSP adds on top of the AI SDK (new work, not Renesas-provided)

- **Ubuntu 26.04 "resolute" userland** via mmdebstrap (AI SDK is Yocto-only;
  zero deb packaging exists upstream — confirmed by grep).
- **GNOME via mutter on Wayland.** The AI SDK distro removes x11 and ships
  Weston 13 only; the Mali blob has wayland/fbdev variants only. Integration
  tricks ported from `~/dev-nvme/nxp/std/debian-13/flexbuild` (proven on
  i.MX95): Mesa client libs (`libEGL/libGLESv2/libgbm/…`) moved aside and
  replaced by Mali's, `gpuconfig` patchelf's `libmutter` `libGL.so.1 →
  libGLESv2.so.2` before GDM, `WaylandEnable=true` forced, COGL/CLUTTER gles2
  env, `gen-monitors.py` for HDMI.
- gst-omx/vspmfilter/mmngr/vspmif userspace **rebuilt in-chroot against
  GStreamer 1.26** (upstream pins 1.22.12 — API-stable, but this is a version
  bump Renesas never tested).
- udev rules for accel devices (AI SDK image runs as root; GNOME can't).

## Known gaps / must verify on hardware

1. **Board**: recipes carry **EVK ver1/ver2 DTBs only** — no Kakip, no RDK.
   `create_image.sh` picks the EVK DTB. A Kakip/RDK build needs its DT ported
   onto 6.1.141-cip43 (Kakip's own tree `~/dev-nvme/kakip/kaki/kakip_linux`
   is 5.10.145 — DT nodes need forward-porting, not copy-paste).
2. **mutter × Mali blob**: patchelf trick is proven on i.MX95 + GNOME, not yet
   on RZ/V2H + resolute's mutter. First-boot check: `journalctl -u gdm` for
   EGL init, `eglinfo` under the GNOME session.
3. **gst-omx on GStreamer 1.26**: builds from 1.22 branch; if meson rejects
   the newer GStreamer, pin `libgstreamer1.0-dev` from -security pocket or
   backport — flagged in `build_gst_plugins.sh`.
4. **Xwayland** clients render via llvmpipe (Mali has no GLX) — GNOME shell
   itself is native Wayland and unaffected.
5. **mali_kbase KM patches** include a v5.10-compat patch; if it fails to
   apply against 6.1 sources, drop it (the KM tarball may already be 6.1-ready
   — the Yocto recipe applies the same list, so failure is unexpected).
6. Prebuilt **BL2/FIP are EVK-signed** (`board_setup/xSPI.zip`); fine for EVK
   bring-up, rebuild via `--from-source` + bptool for other boards.

## 2026-07-10 restructure — flexbuild-style, yocto-tree-independent

Component pins moved to `configs/components/*.mk` (fetch helpers in
`include/download.mk`). AI SDK patches are now **baked into each component's
roseapple-dev fork** as commits (Renesas authorship preserved) — the only
in-repo patch dir left is `patch/mali-km/` (Mali KM ships as a blob tarball,
not a git repo, so it is patched at build time). See `patch/PROVENANCE.md`.
Closed blobs cached in `dl/` with `SHA256SUMS`; sources: `BLOB_BASE_URL`
(self-hosted, preferred for CI) or the local AI SDK package as fallback.
